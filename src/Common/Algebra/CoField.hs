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
module Common.Algebra.CoField 
   ( CoSemiRing(..), CoRing(..), CoField(..)
   , SmartField(..)
   ) where

import Common.Algebra.Group
import Common.Algebra.Field
import Common.Algebra.CoGroup
import Common.Algebra.SmartGroup
import Control.Arrow

class CoSemiRing a where
   -- additive
   isPlus  :: a -> Maybe (a, a)
   isZero  :: a -> Bool
   -- multiplicative
   isTimes :: a -> Maybe (a, a)
   isOne   :: a -> Bool

-- Minimal complete definition: plusInverse or <->
class CoSemiRing a => CoRing a where
   isNegate :: a -> Maybe a
   isMinus  :: a -> Maybe (a, a)
   -- default definition
   isMinus _ = Nothing
   
class CoRing a => CoField a where
   isRecip    :: a -> Maybe a
   isDivision :: a -> Maybe (a, a)
   -- default definition
   isDivision _ = Nothing
   
instance CoSemiRing a => CoMonoid (Additive a) where
   isEmpty  = isZero . fromAdditive
   isAppend = fmap (Additive *** Additive) . isPlus . fromAdditive
   
instance CoRing a => CoGroup (Additive a) where
   isInverse   = fmap Additive . isNegate . fromAdditive
   isAppendInv = fmap (Additive *** Additive) . isMinus . fromAdditive
   
instance CoSemiRing a => CoMonoid (Multiplicative a) where
   isEmpty  = isOne . fromMultiplicative
   isAppend = fmap (Multiplicative *** Multiplicative) . isTimes . fromMultiplicative
   
instance CoField a => CoGroup (Multiplicative a) where
   isInverse   = fmap Multiplicative . isRecip . fromMultiplicative
   isAppendInv = fmap (Multiplicative *** Multiplicative) . isDivision . fromMultiplicative
   
instance CoSemiRing a => CoMonoidZero (Multiplicative a) where
   isMonoidZero = isZero . fromMultiplicative

------------------------------------------------------------------

newtype SmartField a = SmartField {fromSmartField :: a}

instance (CoField a, Field a) => SemiRing (SmartField a) where
   SmartField a <+> SmartField b = SmartField $ fromAdditive $ fromSmartGroup $ 
      SmartGroup (Additive a) <> SmartGroup (Additive b)
   zero  = SmartField zero
   SmartField a <*> SmartField b = SmartField $ fromMultiplicative $ 
      fromSmartGroup $ fromSmartZero $
         SmartZero (SmartGroup (Multiplicative a)) <> 
         SmartZero (SmartGroup (Multiplicative b))
   one   = SmartField one

instance (CoField a, Field a) => Ring (SmartField a) where
   plusInverse = SmartField . fromAdditive . fromSmartGroup . inverse 
               . SmartGroup . Additive . fromSmartField
   SmartField a <-> SmartField b = SmartField $ fromAdditive $ fromSmartGroup $ 
      SmartGroup (Additive a) <>- SmartGroup (Additive b)

instance (CoField a, Field a) => Field (SmartField a) where
   timesInverse = SmartField . fromMultiplicative . fromSmartGroup . inverse 
                . SmartGroup . Multiplicative . fromSmartField
   SmartField a </> SmartField b = SmartField $ fromMultiplicative $ 
      fromSmartGroup $ 
         SmartGroup (Multiplicative a) <>- SmartGroup (Multiplicative b)