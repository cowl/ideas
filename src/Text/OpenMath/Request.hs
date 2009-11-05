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
module Text.OpenMath.Request (xmlToRequest) where

import Service.TypedAbstractService
import Text.XML
import Control.Monad
import Common.Context
import Common.Exercise
import Common.Strategy hiding (fail)
import Common.Utils (splitAtElem, splitsWithElem)
import Text.OpenMath.Object
import Data.Char
import Data.Maybe

extractString :: String -> XML -> Either String String
extractString s = liftM getData . findChild s

xmlToRequest :: XML -> (OMOBJ -> Maybe a) -> Exercise a -> Either String (State a, StrategyLocation, Maybe a)
xmlToRequest xml fromOpenMath ex = do
   unless (name xml == "request") $
      fail "XML document is not a request" 
   loc     <- optional (extractLocation "location" xml)
   term    <- extractExpr "term" xml
   context <- optional (extractString "context" xml)
   answer  <- optional (extractExpr "answer" xml)
   t  <- maybe (fail "invalid omobj") return (fromOpenMath term)
   mt <- case answer of
            Nothing -> return Nothing 
            Just o  -> return $ fromOpenMath o
   return
      ( State
           { exercise = ex
           , prefix   = case context of
                           Just s  -> Just $ getPrefix2 s (strategy ex)
                           Nothing -> Just $ emptyPrefix (strategy ex)
           , context  = case context of 
                           Just s  -> putInContext2 s t
                           Nothing -> inContext t
           }
      , fromMaybe topLocation loc
      , mt
      )

-----------------------------------------------------------
putInContext2 :: String -> a -> Context a
putInContext2 s = fromMaybe inContext $ do
   (_, s2) <- splitAtElem ';' s
   c       <- parseContext s2
   return (flip fmap c . const)

getPrefix2 :: String -> LabeledStrategy (Context a) -> Prefix (Context a)
getPrefix2 s ls = fromMaybe (emptyPrefix ls) $ do
   (s1, _) <- splitAtElem ';' s
   case reads s1 of
      [(is, xs)] | all isSpace xs -> return (makePrefix is ls)
      _ -> Nothing 

optional :: Either String a -> Either String (Maybe a)
optional = Right . either (const Nothing) Just

extractLocation :: String -> XML -> Either String StrategyLocation
extractLocation s xml = do
   c <- findChild s xml
   case parseStrategyLocation (getData c) of
      Just loc -> return loc
      _        -> fail "invalid location"

extractExpr :: String -> XML -> Either String OMOBJ
extractExpr n xml =
   case findChild n xml of 
      Just expr -> 
         case children expr of 
            [this] -> xml2omobj this
            _ -> fail $ "error in " ++ show (n, xml)
      _ -> fail $ "error in " ++ show (n, xml)

-- Legacy code: remove!
parseContext :: String -> Maybe (Context ())
parseContext s
   | all isSpace s = 
        return $ makeContext emptyEnv ()
   | otherwise = do
        pairs <- mapM (splitAtElem '=') (splitsWithElem ',' s)
        let env = foldr (uncurry storeEnv) emptyEnv pairs
        return $ makeContext env ()