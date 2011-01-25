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
-- Type classes and instances.
--
-----------------------------------------------------------------------------
module Common.Classes 
   ( Apply, apply, applyAll, applicable, applyD, applyM
   , Collection, singleton, fromList
   ) where

import Common.Utils (safeHead)
import Data.Maybe
import Data.Monoid
import qualified Data.Set as S

-----------------------------------------------------------
-- * Type class |Apply|

-- | A type class for functors that can be applied to a value. Transformation, 
-- Rule, and Strategy are all instances of this type class. 
class Apply t where
   applyAll :: t a -> a -> [a]  -- ^ Returns zero or more results

-- | Returns zero or one results
apply :: Apply t => t a -> a -> Maybe a
apply ta = safeHead . applyAll ta

-- | Checks whether the functor is applicable (at least one result)
applicable :: Apply t => t a -> a -> Bool
applicable ta = isJust . apply ta

-- | If not applicable, return the current value (as default)
applyD :: Apply t => t a -> a -> a
applyD ta a = fromMaybe a (apply ta a)

-- | Same as apply, except that the result (at most one) is returned in some monad
applyM :: (Apply t, Monad m) => t a -> a -> m a
applyM ta = maybe (fail "applyM") return . apply ta

-----------------------------------------------------------
-- * Type class |Collection|

class Collection f where
   singleton :: a -> f a
   fromList  :: Monoid (f a) => [a] -> f a
   -- default definition
   fromList = mconcat . map singleton

instance Collection [] where
   singleton = return
   fromList  = id
   
instance Collection S.Set where
   singleton = S.singleton