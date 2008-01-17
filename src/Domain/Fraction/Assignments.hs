module Domain.Fraction.Assignments where

import Domain.Fraction.Zipper
import Domain.Fraction.Generator
import Domain.Fraction.Frac
import Domain.Fraction.Strategies
import Domain.Fraction.Parser
import Domain.Fraction.Rules

import Common.Assignment
import Common.Strategy
import Control.Monad
import System.Random

simplAssignment :: Assignment FracInContext
simplAssignment = Assignment
   { shortTitle    = "Fractions" 
   , parser        = \s -> case parseFrac s of
                              (p, [])   -> Right (inContext p)
                              (p, msgs) -> Left  (text (show msgs), Just (inContext p))
   , prettyPrinter = ppFracPars . noContext
   , equivalence   = \x y -> noContext x ~= noContext y
   , equality      = \x y -> noContext x == noContext y
   , finalProperty = isSimplified . noContext
   , ruleset       = map liftFracRule fracRules
   , strategy      = unlabel toSimple
   , generator     = liftM inContext generateFrac
   , suitableTerm  = \f -> (nf $ noContext f) /= Nothing 
                           && not (isSimplified $ noContext f)
   , configuration = defaultConfiguration
   }


{-
dnfAssignment :: Assignment FracInContext
dnfAssignment = Assignment
   { shortTitle    = "Proposition to DNF" 
   , parser        = \s -> case parseFracPars s of
                              (p, [])   -> Right (inContext p)
                              (p, msgs) -> Left  (text (show msgs), Just (inContext p))
   , prettyPrinter = ppFracPars . noContext
   , equivalence   = \x y -> noContext x ~= noContext y
   , equality      = \x y -> noContext x == noContext y
   , finalProperty = isDNF . noContext
   , ruleset       = map liftFracRule logicRules
   , strategy      = unlabel toDNF
   , generator     = let check p = not (isDNF p) && countEquivalences p < 2 && countBinaryOperators p <= 3
                     in liftM inContext generateFrac -- (suitableFrac check)
   , suitableTerm  = \p -> countEquivalences (noContext p) < 2 && countBinaryOperators (noContext p) <= 3
   , configuration = defaultConfiguration
   }
-}