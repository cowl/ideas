-----------------------------------------------------------------------------
-- Copyright 2018, Ideas project team. This file is distributed under the
-- terms of the Apache License 2.0. For more information, see the files
-- "LICENSE.txt" and "NOTICE.txt", which are included in the distribution.
-----------------------------------------------------------------------------
-- |
-- Maintainer  :  bastiaan.heeren@ou.nl
-- Stability   :  provisional
-- Portability :  portable (depends on ghc)
--
-- Datatype for representing a derivation (parameterized both in the terms
-- and the steps)
--
-----------------------------------------------------------------------------

module Ideas.Common.Derivation
   ( -- * Data type
     Derivation
     -- * Constructing a derivation
   , emptyDerivation, prepend, extend
   , merge, mergeBy, mergeStep
     -- * Conversion to/from list
   , derivationToList, derivationFromList
     -- * Querying a derivation
   , isEmpty, derivationLength, terms, steps, triples
   , firstTerm, lastTerm, lastStep, withoutLast
   , updateSteps, derivationM, splitStep
   ) where

import Data.Maybe
import Data.Monoid
import Ideas.Common.Classes
import Ideas.Common.Rewriting
import qualified Data.Foldable as F
import qualified Data.Sequence as S

-----------------------------------------------------------------------------
-- Data type definition and instances

data Derivation s a = D a (S.Seq (s, a))
   deriving Eq

instance (Show s, Show a) => Show (Derivation s a) where
   show (D a xs) = unlines $
      show a : concatMap (\(r, b) -> ["   => " ++ show r, show b]) (F.toList xs)

instance Functor (Derivation s) where
   fmap = mapSecond

instance BiFunctor Derivation where
   biMap f g (D a xs) = D (g a) (fmap (biMap f g) xs)

instance (IsTerm s, IsTerm a) => IsTerm (Derivation s a) where 
   toTerm = TList . derivationToList toTerm toTerm
   fromTerm (TList xs) = derivationFromList fromTerm fromTerm xs
   fromTerm _ = fail "not a derivation"

-----------------------------------------------------------------------------
-- Constructing a derivation

emptyDerivation :: a -> Derivation s a
emptyDerivation a = D a S.empty

prepend :: (a, s) -> Derivation s a -> Derivation s a
prepend (a, s) (D b xs) = D a ((s, b) S.<| xs)

extend :: Derivation s a -> (s, a) -> Derivation s a
extend (D a xs) p = D a (xs S.|> p)

merge :: Eq a => Derivation s a -> Derivation s a -> Maybe (Derivation s a)
merge = mergeBy (==)

mergeBy :: (a -> a -> Bool) -> Derivation s a -> Derivation s a -> Maybe (Derivation s a)
mergeBy eq d@(D a xs) (D b ys)
   | eq (lastTerm d) b = Just $ D a (xs <> ys)
   | otherwise = Nothing


mergeStep :: Derivation s a -> s -> Derivation s a -> Derivation s a
mergeStep (D a xs) s (D b ys) = D a (xs <> ((s, b) S.<| ys))

-----------------------------------------------------------------------------
-- Conversion to/from list

derivationToList :: (s -> b) -> (a -> b) -> Derivation s a -> [b]
derivationToList f g d = 
   g (firstTerm d) : concat [ [f s, g a] | (_, s, a) <- triples d ]

derivationFromList :: Monad m => (b -> m s) -> (b -> m a) -> [b] -> m (Derivation s a)
derivationFromList f g = rec
 where
   rec []  = fail "derivationFromList"
   rec [b] = emptyDerivation <$> g b
   rec (b1:b2:bs) = curry prepend <$> g b1 <*> f b2 <*> rec bs

-----------------------------------------------------------------------------
-- Querying a derivation

-- | Tests whether the derivation is empty
isEmpty :: Derivation s a -> Bool
isEmpty (D _ xs) = S.null xs

-- | Returns the number of steps in a derivation
derivationLength :: Derivation s a -> Int
derivationLength (D _ xs) = S.length xs

-- | All terms in a derivation
terms :: Derivation s a -> [a]
terms (D a xs) = a:map snd (F.toList xs)

-- | All steps in a derivation
steps :: Derivation s a -> [s]
steps (D _ xs) = map fst (F.toList xs)

-- | The triples of a derivation, consisting of the before term, the
-- step, and the after term.
triples :: Derivation s a -> [(a, s, a)]
triples d = zip3 (terms d) (steps d) (tail (terms d))

firstTerm :: Derivation s a -> a
firstTerm = head . terms

lastTerm :: Derivation s a -> a
lastTerm = last . terms

lastStep:: Derivation s a -> Maybe s
lastStep = listToMaybe . reverse . steps

withoutLast :: Derivation s a -> Derivation s a
withoutLast d@(D a xs) =
   case S.viewr xs of
      S.EmptyR  -> d
      ys S.:> _ -> D a ys

updateSteps :: (a -> s -> a -> t) -> Derivation s a -> Derivation t a
updateSteps f d =
   let ts   = [ f a b c | (a, b, c) <- triples d ]
       x:xs = terms d
   in D x (S.fromList (zip ts xs))

-- | Apply a monadic function to each term, and to each step
derivationM :: Monad m => (s -> m ()) -> (a -> m ()) -> Derivation s a -> m ()
derivationM f g (D a xs) = g a >> mapM_ (\(s, b) -> f s >> g b) (F.toList xs)

splitStep :: (s -> Bool) -> Derivation s a -> Maybe (Derivation s a, s, Derivation s a)
splitStep p (D a xs) = 
   case S.viewl xs2 of
      S.EmptyL -> Nothing
      (s, b) S.:< ys -> Just (D a xs1, s, D b ys)
 where
   (xs1, xs2) = S.breakl (p . fst) xs