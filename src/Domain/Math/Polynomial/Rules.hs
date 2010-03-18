-----------------------------------------------------------------------------
-- Copyright 2009, Open Universiteit Nederland. This file is distributed 
-- under the terms of the GNU General Public License. For more information, 
-- see the file "LICENSE.txt", which is included in the distribution.
-----------------------------------------------------------------------------
-- |
-- Maintainer  :  bastiaan.heeren@ou.nl
-- Stability   :  provisional
-- Portability :  portable (depends on ghc)
--
-----------------------------------------------------------------------------
module Domain.Math.Polynomial.Rules where

import Common.Apply
import Common.Context
import Common.Transformation
import Common.Traversable
import Common.Uniplate (universe, uniplate)
import Common.Utils
import Common.View hiding (simplify)
import Control.Monad
import Data.List (nub, (\\), sort, sortBy)
import Data.Maybe
import Data.Ratio
import Domain.Math.Approximation (precision)
import Domain.Math.Clipboard
import Domain.Math.Data.OrList
import Domain.Math.Data.Relation
import Domain.Math.Equation.CoverUpRules hiding (coverUpPlus)
import Domain.Math.Expr
import Domain.Math.Numeric.Views
import Domain.Math.Polynomial.CleanUp
import Domain.Math.Polynomial.Views
import Domain.Math.Power.Views
import Domain.Math.Simplification
import Prelude hiding (repeat, (^), replicate)
import qualified Domain.Math.Data.Polynomial as P
import qualified Domain.Math.SquareRoot.Views as SQ
import qualified Prelude

------------------------------------------------------------
-- Rule collection

linearRules :: [Rule (Context (Equation Expr))]
linearRules = map liftToContext $
   [ removeDivision, ruleMulti merge, ruleMulti distributeTimes
   , varToLeft, coverUpNegate, coverUpTimes
   ] ++
   map ($ oneVar) 
   [coverUpPlusWith, coverUpMinusLeftWith, coverUpMinusRightWith]


quadraticRules :: [Rule (OrList (Equation Expr))]
quadraticRules = -- abcFormula
   [ ruleOnce commonFactorVar, ruleOnce noLinFormula, ruleOnce niceFactors
   , ruleOnce simplerA, mulZero, coverUpPower, squareBothSides
   ] ++
   map (ruleOnce . ($ oneVar)) 
     [coverUpPlusWith, coverUpMinusLeftWith, coverUpMinusRightWith] ++
   [ ruleOnce coverUpTimes, ruleOnce coverUpNegate, ruleOnce coverUpNumerator
   , ruleOnce prepareSplitSquare, ruleOnce factorLeftAsSquare
   , ruleOnce2 (ruleSomewhere merge), ruleOnce cancelTerms
   , ruleOnce2 (ruleSomewhere distributeTimes)
   , ruleOnce2 (ruleSomewhere distributionSquare), ruleOnce flipEquation 
   , ruleOnce moveToLeft, ruleMulti2 (ruleSomewhere simplerSquareRoot)
   ]
   
higherDegreeRules :: [Rule (OrList (Equation Expr))]
higherDegreeRules = 
   [ allPowerFactors, sameFactor
   ] ++ quadraticRules

------------------------------------------------------------
-- General form rules: ax^2 + bx + c = 0

-- ax^2 + bx = 0 
commonFactorVar :: Rule (Equation Expr) 
commonFactorVar = rhsIsZero commonFactorVarNew

commonFactorVarNew :: Rule Expr
commonFactorVarNew = makeSimpleRule "common factor var" $ \expr -> do
   (x, (a, b, c)) <- match (polyNormalForm rationalView >>> second quadraticPolyView) expr
   guard (c == 0 && b /= 0)
   -- also search for constant factor
   let d = (if a<0 && b<0 then negate else id) (gcdFrac a b)
   return (fromRational d .*. Var x .*. (fromRational (a/d) .*. Var x .+. fromRational (b/d)))


-- ax^2 + c = 0
noLinFormula :: Rule (Equation Expr)
noLinFormula = makeSimpleRule "no linear term b" $ \(lhs :==: rhs) -> do
   guard (rhs == 0)
   (x, (a, b, c)) <- match (polyNormalForm rationalView >>> second quadraticPolyView) lhs
   guard (b == 0 && c /= 0)
   return $ 
      if a>0 then fromRational a .*. (Var x .^. 2) :==: fromRational (-c)
             else fromRational (-a) .*. (Var x .^. 2) :==: fromRational c

-- search for (X+A)*(X+B) decomposition 
niceFactors :: Rule (Equation Expr)
niceFactors = rhsIsZero niceFactorsNew

-- search for (X+A)*(X+B) decomposition 
niceFactorsNew :: Rule Expr
niceFactorsNew = makeSimpleRuleList "nice factors" $ \expr -> do
   let sign t@(x, (a, b, c)) = if a== -1 then (x, (1, -b, -c)) else t 
   (x, (a, rb, rc)) <- liftM sign (matchM (polyNormalForm rationalView >>> second quadraticPolyView) expr)
   guard (a==1)
   b <- isInt rb
   c <- isInt rc
   let ok (i, j) = i+j == b
       f  (i, j) 
          | i == j = -- special case
              (Var x + fromInteger i) ^ 2
          | otherwise =
              (Var x + fromInteger i) * (Var x + fromInteger j)
   map f (filter ok (factors c))

rhsIsZero :: Rule Expr -> Rule (Equation Expr)
rhsIsZero r = makeSimpleRuleList (name r) $ \(lhs :==: rhs) -> do
   guard (rhs == 0)
   a <- applyAll r lhs
   return (a :==: rhs)

simplerA :: Rule (Equation Expr)
simplerA = makeSimpleRule "simpler polynomial" $ \(lhs :==: rhs) -> do
   guard (rhs == 0)
   (x, (ra, rb, rc)) <- match (polyNormalForm rationalView >>> second quadraticPolyView) lhs
   [a, b, c] <- mapM isInt [ra, rb, rc] 
   let d = (a `gcd` b `gcd` c) * signum a
   guard (d `notElem` [0, 1])
   return (build quadraticView (x, fromInteger (a `div` d), fromInteger (b `div` d), fromInteger (c `div` d)) :==: 0)

------------------------------------------------------------
-- General form rules: expr = 0

-- Rule must be symmetric in side of equation
mulZero :: Rule (OrList (Equation Expr))
mulZero = makeSimpleRuleList "multiplication is zero" $ onceJoinM bothSides
 where
   bothSides eq = oneSide eq `mplus` oneSide (flipSides eq)
   oneSide (lhs :==: rhs) = do
      guard (rhs == 0)
      (_, xs) <- matchM productView lhs
      guard (length xs > 1)
      let f e = case match (polyNormalForm rationalView >>> second linearPolyView) e of
                   -- special cases (simplify immediately, as in G&R)
                   Just (x, (a, b)) 
                      | a == 1 -> 
                           Var x :==: fromRational (-b)
                      | a == -1 -> 
                           Var x :==: fromRational b
                   _ -> e :==: 0 
      return $ orList $ map f xs 

------------------------------------------------------------
-- Constant form rules: expr = constant

-- Use this configuration for covering-up plus and minus symbols!
-- Prevent    (x^2+3x)+5 = 0   to be covered up
oneVar :: ConfigCoverUp
oneVar = configCoverUp
   { configName        = Just "one var"
   , predicateCovered  = \a -> p1 a || p2 a
   , predicateCombined = noVars
   , coverLHS          = True
   , coverRHS          = True
   }
 where 
   p1 = (==1) . length . collectVars
   -- predicate p2 tests for cases such as 12*(x^2-3*x)+8 == 56
   p2 a = fromMaybe False $ do
      (x, y) <- match timesView a
      return (hasVars x /= hasVars y)

------------------------------------------------------------
-- Top form rules: expr1 = expr2

-- Do not simplify (5+sqrt 53)/2
simplerSquareRoot :: Rule Expr
simplerSquareRoot = makeSimpleRule "simpler square root" $ \e -> do
   xs <- f e
   guard (not (null xs))
   new <- canonical (SQ.squareRootViewWith rationalView) e
   ys <- f new
   guard (xs /= ys)
   return new
 where
   -- return numbers under sqrt symbol
   f :: Expr -> Maybe [Rational]
   f e = liftM sort $ sequence [ match rationalView e | Sqrt e <- universe e ]
 

cancelTerms :: Rule (Equation Expr)
cancelTerms = makeSimpleRule "cancel terms" $ \(lhs :==: rhs) -> do
   xs <- match sumView lhs
   ys <- match sumView rhs
   let zs = filter (`elem` ys) (nub xs)
   guard (not (null zs))
   let without as = build sumView (as \\ zs)
   return (without xs :==: without ys)

-- Two out of three "merkwaardige producten"
distributionSquare :: Rule Expr
distributionSquare = makeSimpleRule "distribution square" f
 where
   f (Sym s [a :+: b, Nat 2]) | s == powerSymbol =
      return ((a .^. 2) .+. (2 .*. a .*. b) + (b .^. 2))
   f (Sym s [a :-: b, Nat 2]) | s == powerSymbol =
      return ((a .^. 2) .-. (2 .*. a .*. b) + (b .^. 2))
   f _ = Nothing

-- a^2 == b^2
squareBothSides :: Rule (OrList (Equation Expr))
squareBothSides = makeSimpleRule "square both sides" $ onceJoinM f 
 where
   f (Sym s1 [a, Nat 2] :==: Sym s2 [b, Nat 2]) | all (==powerSymbol) [s1, s2] = 
      return $ orList [a :==: b, a :==: -b]
   f _ = Nothing

-- prepare splitting a square; turn lhs into x^2+bx+c s.t. (b/2)^2 is c
prepareSplitSquare :: Rule (Equation Expr)
prepareSplitSquare = makeSimpleRule "prepare split square" $ \(lhs :==: rhs) -> do
   d <- match rationalView rhs
   let myView = polyNormalForm rationalView >>> second quadraticPolyView
   (x, (a, b, c)) <- match myView lhs
   let newC   = (b/2)*(b/2)
       newRHS = d + newC - c
   guard (a==1 && b/=0 && c /= newC)
   return (build myView (x, (a, b, newC)) :==: build rationalView newRHS)

-- factor left-hand side into (ax + c)^2
factorLeftAsSquare :: Rule (Equation Expr)
factorLeftAsSquare = makeSimpleRule "factor left as square" $ \(lhs :==: rhs) -> do
   guard (noVars rhs)
   (x, (a, b, c)) <- match (polyNormalForm rationalView >>> second quadraticPolyView) lhs
   let h = b/2
   guard (a==1 && b/=0 && h*h == c)
   return ((Var x + build rationalView h)^2 :==: rhs) 

-- Afterwards, merge, sort, and (possibly) change sign
flipEquation :: Rule (Equation Expr)
flipEquation = makeSimpleRule "flip equation" $ \(lhs :==: rhs) -> do
   guard (hasVars rhs && noVars lhs)
   let new = fmap (applyListD [sortT, mergeT]) (rhs :==: lhs)
   return $ applyD signT new

-- Afterwards, merge and sort
moveToLeft :: Rule (Equation Expr)
moveToLeft = makeSimpleRule "move to left" $ \(lhs :==: rhs) -> do
   guard (rhs /= 0)
   let complex = case fmap (filter hasVars) $ match sumView (applyD merge lhs) of
                    Just xs | length xs >= 2 -> True
                    _ -> False
   guard (hasVars lhs && (hasVars rhs || complex))
   let new = applyD mergeT $ applyD sortT $ lhs - rhs
   return (new :==: 0)

ruleApproximate :: Rule (Relation Expr)
ruleApproximate = makeSimpleRule "approximate" $ \relation -> do
   lhs :==: rhs <- match equationView relation
   guard (not (simplify rhs `belongsTo` rationalView))
   x <- getVariable lhs
   d <- match doubleView rhs
   let new = fromDouble (precision 4 d)
   return (Var x .~=. new)

------------------------------------------------------------
-- Helpers and Rest

factors :: Integer -> [(Integer, Integer)]
factors n = concat [ [(a, b), (negate a, negate b)] | a <- [1..h], let b = n `div` a, a*b == n ]
 where h = floor (sqrt (abs (fromIntegral n)))

isInt :: MonadPlus m => Rational -> m Integer
isInt r = do
   guard (denominator r == 1)
   return (numerator r)

gcdFrac :: Rational -> Rational -> Rational
gcdFrac r1 r2 = fromMaybe 1 $ do 
   a <- isInt r1
   b <- isInt r2
   return (fromInteger (gcd a b))

-----------------------------------------------------------
-------- Rules From HDE

-- X*A + X*B = X*C + X*D
allPowerFactors :: Rule (OrList (Equation Expr))
allPowerFactors = makeSimpleRule "all power factors" $ onceJoinM $ \(lhs :==: rhs) -> do
   xs <- match (sumView >>> listView powerFactorView) lhs
   ys <- match (sumView >>> listView powerFactorView) rhs
   case unzip3 (filter ((/=0) . snd3) (xs ++ ys)) of
      (s:ss, _, ns) | all (==s) ss -> do
         let m = minimum ns 
             make = build (sumView >>> listView powerFactorView) . map f
             f (s, i, n) = (s, i, n-m)
         guard (m > 0 && length ns > 1)
         return $ orList [Var s :==: 0, make xs :==: make ys]
      _ -> Nothing

-- A*B = A*C  implies  A=0 or B=C
sameFactor :: Rule (OrList (Equation Expr))
sameFactor = makeSimpleRule "same factor" $ onceJoinM $ \(lhs :==: rhs) -> do
   (b1, xs) <- match productView lhs
   (b2, ys) <- match productView rhs
   (x, y) <- safeHead [ (x, y) | x <- xs, y <- ys, x==y, hasVars x ] -- equality is too strong?
   return $ orList [ x :==: 0, build productView (b1, xs\\[x]) :==: build productView (b2, ys\\[y]) ]

abcFormula :: Rule (Context (OrList (Equation Expr)))
abcFormula = makeSimpleRule "abc formula" $ withCM $ onceJoinM $ \(lhs :==: rhs) -> do
   guard (rhs == 0)
   (x, (a, b, c)) <- matchM (polyNormalForm rationalView >>> second quadraticPolyView) lhs
   addListToClipboard ["a", "b", "c"] (map fromRational [a, b, c])
   let discr = b*b - 4 * a * c
       sqD   = sqrt (fromRational discr)
   addToClipboard "D" (fromRational discr)
   case compare discr 0 of
      LT -> return false
      EQ -> return $ return $ 
         Var x :==: (-fromRational b) / (2 * fromRational a)
      GT -> return $ orList
         [ Var x :==: (-fromRational b + sqD) / (2 * fromRational a)
         , Var x :==: (-fromRational b - sqD) / (2 * fromRational a)
         ]

higherSubst :: Rule (Context (Equation Expr))
higherSubst = makeSimpleRule "higher subst" $ withCM $ \(lhs :==: rhs) -> do
   guard (rhs == 0)
   let myView = polyView >>> second trinomialPolyView
   (x, ((a, n1), (b, n2), (c, n3))) <- matchM myView lhs
   guard (n1 == 0 && n2 > 1 && n3 `mod` n2 == 0 && x /= "p")
   let new = build myView ("p", ((a, 0), (b, 1), (c, n3 `div` n2)))
   addToClipboard "subst" (toExpr (Var "p" :==: Var x .^. fromIntegral n2))
   return (new :==: 0)

substBackVar :: (Crush f, Crush g) => Rule (Context (f (g Expr)))
substBackVar = makeSimpleRule "subst back var" $ withCM $ \a -> do
   expr <- lookupClipboard "subst"
   case fromExpr expr of
      Just (Var p :==: rhs) -> do
         guard (p `elem` concatMap collectVars (concatMap crush (crush a)))
         return (fmap (fmap (subst p rhs)) a)
      _ -> fail "no subst in clipboard"
 where
   subst a b (Var c) | a==c = b
   subst a b expr = build (map (subst a b) cs)
    where (cs, build) = uniplate expr

exposeSameFactor :: Rule (Equation Expr)
exposeSameFactor = makeSimpleRuleList "expose same factor" $ \(lhs :==: rhs) -> do 
   (bx, xs) <- matchM (productView) lhs
   (by, ys) <- matchM (productView) rhs
   (nx, ny) <- [ (xs, new) | x <- xs, suitable x, new <- exposeList x ys ] ++
               [ (new, ys) | y <- ys, suitable y, new <- exposeList y xs ]
   return (build productView (bx, nx) :==: build productView (by, ny))
 where
   suitable p = fromMaybe False $ do 
      (_, _, b) <- match (linearViewWith rationalView) p
      guard (b /= 0)
      return True
   
   exposeList _ [] = []
   exposeList a (b:bs) = map (++bs) (expose a b) ++ map (b:) (exposeList a bs)
   
   expose a b = do
      (s1, p1) <- matchM (polyViewWith rationalView) a
      (s2, p2) <- matchM (polyViewWith rationalView) b
      guard (s1==s2)
      case P.division p2 p1 of
         Just p3 -> return $ map (\p -> build (polyViewWith rationalView) (s1,p)) [p1, p3]
         Nothing -> []

---------------------------------------------------------
-- From LinearEquations

-------------------------------------------------------
-- Transformations

plusT, minusT :: Functor f => Expr -> Transformation (f Expr)
plusT  e = makeTrans $ return . fmap (applyD mergeT . (.+. e))
minusT e = makeTrans $ return . fmap (applyD mergeT . (.-. e))

timesT :: Functor f => Expr -> Transformation (f Expr)
timesT e = makeTrans $ \eq -> do 
   r <- match rationalView e
   guard (r /= 0)
   return $ fmap (applyD mergeT . applyD distributionOldT . (e .*.)) eq

divisionT :: Expr -> Transformation (Equation Expr)
divisionT e = makeTrans $ \eq -> do
   r <- match rationalView e
   guard (r /= 0)
   return $ fmap (applyD mergeT . applyD distributionOldT . (./. e)) eq

-- This rule should consider the associativity of multiplication
-- Combine bottom-up, for example:  5*(x-5)*(x+5) 
-- However, in  -2x(2x+10)   (-2x) should be seen as "one term"
distributionT :: Transformation Expr
distributionT = makeTransList f
 where
   f expr = do
      (b, xs) <- matchM simpleProductView expr
      ys      <- rec (combine xs)
      return $ build simpleProductView (b, ys)
   
   combine :: [Expr] -> [Expr]
   combine (x:y:rest) | p x && p y = combine ((x*y):rest)
    where p = maybe False ((==1) . length) . match sumView
   combine []     = []
   combine (x:xs) = x : combine xs
   
   rec :: [Expr] -> [[Expr]]
   rec (a:b:xs) = map (:xs) (g a b) ++ map (a:) (rec (b:xs))
   rec _        = []
   
   g :: Expr -> Expr -> [Expr]
   g a b = do 
      as     <- matchM sumView a
      bs     <- matchM sumView b
      guard (length as > 1 || length bs > 1)
      return $ build sumView [ a .*. b | a <- as, b <- bs ]

mergeT :: Transformation Expr
mergeT = makeTrans $ return . collectLikeTerms

-- high exponents first, non power-factor terms at the end
sortT :: Transformation Expr
sortT = makeTrans $ \e -> do
   xs <- match sumView e
   let f  = fmap (negate . thd3) . match powerFactorView
       ps = sortBy cmp $ zip xs (map f xs)
       cmp (_, ma) (_, mb) = compare ma mb
   return $ build sumView $ map fst ps
   
signT :: Transformation (Equation Expr)
signT = makeTrans $ \(lhs :==: rhs) -> do
   a <- match sumView lhs >>= safeHead
   p <- match productView a
   guard (fst p)
   return (-lhs :==: -rhs)
   
-------------------------------------------------------
-- Rewrite Rules

varToLeft :: Relational f => Rule (f Expr)
varToLeft = makeRule "variable to left" $ flip supply1 minusT $ \eq -> do
   (x, a, _) <- match (linearViewWith rationalView) (rightHandSide eq)
   guard (a/=0)
   return (fromRational a * Var x)

{-
conToRight :: Rule (Equation Expr)
conToRight = makeRule "constant to right" $ flip supply1 minusT $ \eq -> do
   (_, _, b) <- match (linearViewWith rationalView) (getLHS eq)
   guard (b/=0)
   return (fromRational b)

scaleToOne :: Rule (Equation Expr)
scaleToOne = makeRule "scale to one" $ flip supply1 divisionT $ \eq -> do
   (_, a, _) <- match (linearViewWith rationalView) (getLHS eq)
   guard (a `notElem` [0, 1])
   return (fromRational a) -}

-- factor is always positive due to lcm function
removeDivision :: Relational r => Rule (r Expr)
removeDivision = makeRule "remove division" $ flip supply1 timesT $ \eq -> do
   xs <- match sumView (leftHandSide eq)
   ys <- match sumView (rightHandSide eq)
   -- also consider parts without variables
   zs <- mapM (fmap snd . match productView) (xs ++ ys)
   let f = fmap snd . match (divView >>> second integerView)
   case mapMaybe f (concat zs) of
      [] -> Nothing
      ns -> return (fromInteger (foldr1 lcm ns))

distributeTimes :: Rule Expr
distributeTimes = makeSimpleRuleList "distribution multiplication" $ \expr -> do
   new <- applyAll distributionT expr
   return (applyD mergeT new)

distributeDivision :: Rule Expr
distributeDivision = makeSimpleRule "distribution division" $ \expr -> do
   (a, b) <- match divView expr
   r      <- match rationalView b
   xs     <- match sumView a
   guard (length xs > 1)
   let ys = map (/fromRational r) xs
   return $ build sumView ys

merge :: Rule Expr
merge = makeSimpleRule "merge similar terms" $ \old -> do
   new <- apply mergeT old
   guard (old /= new)
   return new
   
------------------------
-- Old

-- Temporary fix: here we don't care about the terms we apply it to. Only
-- use for cleaning up
distributionOldT :: Transformation Expr
distributionOldT = makeTrans f 
 where
   f (a :*: b) =
      case (match sumView a, match sumView b) of
         (Just as, Just bs) | length as > 1 || length bs > 1 -> 
            return $ build sumView [ a .*. b | a <- as, b <- bs ]
         _ -> Nothing
   f _ = Nothing