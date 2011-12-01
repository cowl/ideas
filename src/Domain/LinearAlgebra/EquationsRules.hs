-----------------------------------------------------------------------------
-- Copyright 2011, Open Universiteit Nederland. This file is distributed
-- under the terms of the GNU General Public License. For more information,
-- see the file "LICENSE.txt", which is included in the distribution.
-----------------------------------------------------------------------------
-- |
-- Maintainer  :  bastiaan.heeren@ou.nl
-- Stability   :  provisional
-- Portability :  portable (depends on ghc)
--
-----------------------------------------------------------------------------
module Domain.LinearAlgebra.EquationsRules where

import Common.Library hiding (simplify)
import Common.Results
import Control.Monad
import Data.List
import Data.Maybe
import Domain.LinearAlgebra.LinearSystem
import Domain.LinearAlgebra.LinearView
import Domain.LinearAlgebra.MatrixRules (covered) -- for context
import Domain.Math.Data.Relation
import Domain.Math.Expr
import Domain.Math.Simplification (simplify)
import Prelude
import Test.QuickCheck

equationsRules :: [Rule (Context (LinearSystem Expr))]
equationsRules =
   [ ruleExchangeEquations, ruleEliminateVar, ruleDropEquation
   , ruleInconsistentSystem
   , ruleScaleEquation, ruleBackSubstitution, ruleIdentifyFreeVariables
   , ruleCoverUpEquation, ruleUncoverEquation, ruleCoverAllEquations
   ]

ruleExchangeEquations :: Rule (Context (LinearSystem Expr))
ruleExchangeEquations = describe "Exchange two equations" $
   simplifySystem $ makeRule "linearalgebra.linsystem.exchange" $
   supply2 descr (evalCM2 args) (\x y -> liftToContext $ exchange x y)
 where
   descr = ("equation 1", "equation 2")
   args ls = do
      mv  <- minvar ls
      eqs <- remaining ls
      i   <- findIndexM (elem mv . getVarsSystem . return) eqs
      cov <- readVar covered
      return (cov, cov + i)

ruleEliminateVar :: Rule (Context (LinearSystem Expr))
ruleEliminateVar = describe "Eliminate a variable (using addition)" $
   simplifySystem $ makeRule "linearalgebra.linsystem.eliminate" $
   supply3 descr (evalCM2 args) (\x y z -> liftToContext $ addEquations x y z)
 where
   descr = ("equation 1", "equation 2", "scale factor")
   args ls = do
      mv <- minvar ls
      hd:rest <- remaining ls
      let getCoef = coefficientOf mv . leftHandSide
      (i, coef) <- headResult [ (i, c) | (i, eq) <- zip [0..] rest, let c = getCoef eq, c /= 0 ]
      guard (getCoef hd /= 0)
      let v = negate coef / getCoef hd
      cov <- readVar covered
      return (i + cov + 1, cov, v)

ruleDropEquation :: Rule (Context (LinearSystem Expr))
ruleDropEquation = describe "Drop trivial equations (such as 0=0)" $
   simplifySystem $ makeEnvRule "linearalgebra.linsystem.trivial" $ withCM2 $ \ls -> do
      i   <- findIndexM (fromMaybe False . testConstants (==)) ls
      modifyVar covered (\n -> if i < n then n-1 else n)
      return (deleteIndex i ls)

ruleInconsistentSystem :: Rule (Context (LinearSystem Expr))
ruleInconsistentSystem = describe "Inconsistent system (0=1)" $
   simplifySystem $ makeEnvRule "linearalgebra.linsystem.inconsistent" $ withCM2 $ \ls -> do
      let stop = [0 :==: 1]
      guard (invalidSystem ls && ls /= stop)
      writeVar covered 1
      return stop

ruleScaleEquation :: Rule (Context (LinearSystem Expr))
ruleScaleEquation = describe "Scale equation to one" $
   simplifySystem $ makeRule "linearalgebra.linsystem.scale" $
   supply2 descr (evalCM2 args) (\x y -> liftToContext $ scaleEquation x y)
 where
   descr = ("equation", "scale factor")
   args ls = do
      cov <- readVar covered
      eq  <- headResult $ drop cov ls
      let expr = leftHandSide eq
      mv <- minvar ls
      guard (coefficientOf mv expr /= 0)
      let coef = 1 / coefficientOf mv expr
      return (cov, coef)

ruleBackSubstitution :: Rule (Context (LinearSystem Expr))
ruleBackSubstitution = describe "Back substitution" $
   simplifySystem $ makeRule "linearalgebra.linsystem.subst" $
   supply3 descr (evalCM2 args) (\x y z -> liftToContext $ addEquations x y z)
 where
   descr = ("equation 1", "equation 2", "scale factor")
   args ls = do
      cov <- readVar covered
      eq  <- headResult (drop cov ls)
      let expr = leftHandSide eq
      mv <- headResult (vars expr)
      i  <- findIndexM ((/= 0) . coefficientOf mv . leftHandSide) (take cov ls)
      let coef = negate $ coefficientOf mv (leftHandSide (ls !! i))
      return (i, cov, coef)

ruleIdentifyFreeVariables :: IsLinear a => Rule (Context (LinearSystem a))
ruleIdentifyFreeVariables = describe "Identify free variables" $
   minorRule $ makeEnvRule "linearalgebra.linsystem.freevars" $ withCM2 $ \ls ->
   let vs = [ head ys | ys <- map (vars . leftHandSide) ls, not (null ys) ]
       f eq =
          let (e1, e2) = splitLinearExpr (`notElem` vs) (leftHandSide eq) -- constant ends up in e1
          in e2 :==: rightHandSide eq - e1
   in return (map f ls)

ruleCoverUpEquation :: Rule (Context (LinearSystem a))
ruleCoverUpEquation = describe "Cover up first equation" $
   minorRule $ makeRule "linearalgebra.linsystem.coverup" $ changeCover succ

ruleUncoverEquation :: Rule (Context (LinearSystem a))
ruleUncoverEquation = describe "Uncover one equation" $
   minorRule $ makeRule "linearalgebra.linsystem.uncover" $ changeCover pred

ruleCoverAllEquations :: Rule (Context (LinearSystem a))
ruleCoverAllEquations = describe "Cove all equations" $
   minorRule $ makeEnvRule "linearalgebra.linsystem.coverall" $ withCM2 $ \ls -> do
      writeVar covered (length ls)
      return ls

-- local helper functions
deleteIndex :: Int -> [a] -> [a]
deleteIndex i xs = ys ++ drop 1 zs
 where (ys, zs) = splitAt i xs

testConstants :: IsLinear a => (a -> a -> Bool) -> Equation a -> Maybe Bool
testConstants f (lhs :==: rhs)
   | hasNoVar lhs && hasNoVar rhs = Just (f lhs rhs)
   | otherwise = Nothing

-- simplify a linear system
simplifySystem :: Rule (Context (LinearSystem Expr)) -> Rule (Context (LinearSystem Expr))
simplifySystem = doAfter $ change (map (fmap f))
 where f = simplifyWith (fmap simplify) linearView

---------------------------------------------------------------------------------
-- Parameterized transformations

exchange :: Int -> Int -> Transformation [a]
exchange i j
   | i >  j    = exchange j i
   | otherwise = makeTrans $ \xs -> do
        guard (i/=j && validEquation i xs && validEquation j xs)
        let (begin, x:rest) = splitAt i xs
            (middle, y:end) = splitAt (j-i-1) rest
        return $ begin++[y]++middle++[x]++end

scaleEquation :: IsLinear a => Int -> a -> Transformation (LinearSystem a)
scaleEquation i a = makeTrans $ \xs -> do
   guard (a `notElem` [0,1] && validEquation i xs)
   let (begin, this:end) = splitAt i xs
   return (begin ++ [fmap (a*) this] ++ end)

addEquations :: IsLinear a => Int -> Int -> a -> Transformation (LinearSystem a)
addEquations i j a = makeTrans $ \xs -> do
   guard (i/=j && validEquation i xs && validEquation j xs)
   let (begin, this:end) = splitAt i xs
       exprj = xs!!j
   return $ begin++[combineWith (+) this (fmap (a*) exprj)]++end

changeCover :: (Int -> Int) -> Transformation (Context (LinearSystem a))
changeCover f = makeEnvTrans $ withCM2 $ \ls -> do
   new <- liftM f (readVar covered)
   guard (new >= 0 && new <= length ls)
   writeVar covered new
   return ls

-- local helper function
combineWith :: (a -> a -> a) -> Equation a -> Equation a -> Equation a
combineWith f (x1 :==: x2) (y1 :==: y2) = f x1 y1 :==: f x2 y2

validEquation :: Int -> [a] -> Bool
validEquation n xs = n >= 0 && n < length xs

--------------------
-- TEMP

-- | The equations that remain to be solved
remaining :: LinearSystem a -> Results (Equations a)
remaining ls = do
   cov <- readVar covered
   return (drop cov ls)

-- | The minimal variable in the remaining equations
minvar :: IsLinear a => LinearSystem a -> Results String
minvar ls = do
   list <- liftM getVarsSystem (remaining ls)
   guard (not $ null list)
   return (minimum list)

systemInNF :: (Arbitrary a, IsLinear a) => Gen (LinearSystem a)
systemInNF = do
   n <- arbitrary
   replicateM n $ liftM2 (:==:) arbitrary arbitrary

toIntegerSystem :: RealFrac a => LinearSystem a -> LinearSystem Integer
toIntegerSystem = map (fmap round)

fromIntegerSystem :: RealFrac a => LinearSystem Integer -> LinearSystem a
fromIntegerSystem = map (fmap fromInteger)

findIndexM :: MonadPlus m => (a -> Bool) -> [a] -> m Int
findIndexM p = maybe mzero return . findIndex p

headResult :: [a] -> Results a
headResult = toResults . listToMaybe