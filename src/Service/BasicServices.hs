-----------------------------------------------------------------------------
-- Copyright 2010, Open Universiteit Nederland. This file is distributed 
-- under the terms of the GNU General Public License. For more information, 
-- see the file "LICENSE.txt", which is included in the distribution.
-----------------------------------------------------------------------------
-- |
-- Maintainer  :  bastiaan.heeren@ou.nl
-- Stability   :  provisional
-- Portability :  portable (depends on ghc)
--
-----------------------------------------------------------------------------
module Service.BasicServices 
   ( -- * Basic Services
     stepsremaining, findbuggyrules, ready, allfirsts, derivation
   , onefirst, applicable, allapplications, apply, generate, generateWith
   ) where

import Common.Library hiding (derivation, applicable, apply)
import Common.Utils (safeHead)
import Data.List
import Data.Maybe
import System.Random (StdGen, newStdGen)
import Control.Monad
import Service.ExercisePackage
import Service.State
import qualified Common.Classes as Apply
      
-- result must be in the IO monad to access a standard random number generator
generate :: ExercisePackage a -> Difficulty -> IO (State a)
generate pkg dif = do 
   stdgen <- newStdGen
   return (generateWith stdgen pkg dif)

generateWith :: StdGen -> ExercisePackage a -> Difficulty -> State a
generateWith rng pkg dif = 
   emptyState pkg (randomTermWith rng dif (exercise pkg))

derivation :: Monad m => Maybe StrategyConfiguration -> State a -> m [(Rule (Context a), Context a)]
derivation mcfg state =
   case (statePrefix state, mcfg) of 
      (Nothing, _) -> fail "Prefix is required"
      -- configuration is only allowed beforehand: hence, the prefix 
      -- should be empty (or else, the configuration is ignored). This
      -- restriction should probably be relaxed later on.
      (Just p, Just cfg) | null (prefixToSteps p) -> 
         let newStrategy = configure cfg (strategy ex)
             newExercise = ex {strategy = newStrategy}
             newPackage  = pkg {exercise = newExercise}
         in rec timeout [] (empyStateContext newPackage (stateContext state))
      _ -> rec timeout [] state
 where
   pkg = exercisePkg state
   ex  = exercise pkg
   timeout = 50 :: Int
 
   rec i acc st = 
      case onefirst st of
         Nothing           -> return (reverse acc)
         Just (r, _, next)
            |  i <= 0      -> fail msg
            | otherwise    -> rec (i-1) ((r, stateContext next) : acc) next
    where
      msg = "Time out after " ++ show timeout ++ " steps. " ++ 
            concatMap f (reverse acc)
      f (r, c) = let s = maybe "???" (prettyPrinter ex) (fromContext c)
                 in "[" ++ show r ++ "]  " ++ s ++ "; "

-- Note that we have to inspect the last step of the prefix afterwards, because
-- the remaining part of the derivation could consist of minor rules only.
allfirsts :: Monad m => State a -> m [(Rule (Context a), Location, State a)]
allfirsts state = 
   case statePrefix state of
      Nothing -> 
         fail "Prefix is required"
      Just p0 ->
         let tree = cutOnStep (stop . lastStepInPrefix) (prefixTree p0 (stateContext state))
             f (r1, _, _) (r2, _, _) = 
                ruleOrdering (exercise (exercisePkg state)) r1 r2
         in return (sortBy f (mapMaybe make (derivations tree)))
 where
   stop (Just (RuleStep r)) = isMajorRule r
   stop _ = False
   
   make d = do
      prefixEnd <- safeHead (reverse (steps d))
      termEnd   <- safeHead (reverse (terms d))
      case lastStepInPrefix prefixEnd of
         Just (RuleStep r) | isMajorRule r -> return
            ( r
            , location termEnd
            , makeState (exercisePkg state) (Just prefixEnd) termEnd
            )
         _ -> Nothing

onefirst :: Monad m => State a -> m (Rule (Context a), Location, State a)
onefirst state = do
   xs <- allfirsts state
   case xs of
      hd:_ -> return hd
      []   -> fail "No step possible"

applicable :: Location -> State a -> [Rule (Context a)]
applicable loc state =
   let p r = not (isBuggyRule r) && Apply.applicable r (setLocation loc (stateContext state))
   in filter p (ruleset (exercise (exercisePkg state)))

allapplications :: State a -> [(Rule (Context a), Location, State a)]
allapplications state = sortBy cmp (xs ++ ys)
 where
   pkg = exercisePkg state
   ex  = exercise pkg
   xs  = concat (allfirsts state)
   ps  = [ (r, loc) | (r, loc, _) <- xs ]
   ys  = maybe [] f (top (stateContext state))
           
   f c = g c ++ concatMap f (allDowns c)
   g c = [ (r, location new, makeState pkg Nothing new)
         | r   <- ruleset ex
         , (r, location c) `notElem` ps
         , new <- applyAll r c
         ]
         
   cmp (r1, loc1, _) (r2, loc2, _) = 
      case ruleOrdering ex r1 r2 of
         EQ   -> loc1 `compare` loc2
         this -> this

-- local helper
setLocation :: Location -> Context a -> Context a 
setLocation loc c0 = fromMaybe c0 (navigateTo loc c0)

-- Two possible scenarios: either I have a prefix and I can return a new one (i.e., still following the 
-- strategy), or I return a new term without a prefix. A final scenario is that the rule cannot be applied
-- to the current term at the given location, in which case the request is invalid.
apply :: Monad m => Rule (Context a) -> Location -> State a -> m (State a)
apply r loc state = maybe applyOff applyOn (statePrefix state)
 where
   applyOn _ = -- scenario 1: on-strategy
      maybe applyOff return $ safeHead
      [ s1 | (r1, loc1, s1) <- fromMaybe [] $ allfirsts state, showId r == showId r1, loc==loc1 ]
      
   applyOff  = -- scenario 2: off-strategy
      case Apply.apply r (setLocation loc (stateContext state)) of
         Just new -> return (makeState (exercisePkg state) Nothing new)
         Nothing  -> fail ("Cannot apply " ++ show r)
       
ready :: State a -> Bool
ready state = isReady (exercise (exercisePkg state)) (stateTerm state)

stepsremaining :: Monad m => State a -> m Int
stepsremaining = liftM length . derivation Nothing

findbuggyrules :: State a -> a -> [Rule (Context a)]
findbuggyrules state a =
   let ex      = exercise (exercisePkg state)
       buggies = filter isBuggyRule (ruleset ex)
       p r     = ruleIsRecognized ex r (stateContext state) (inContext ex a)
   in filter p buggies