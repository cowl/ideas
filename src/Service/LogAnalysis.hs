-----------------------------------------------------------------------------
-- Copyright 2009, Open Universiteit Nederland. This file is distributed 
-- under the terms of the GNU General Public License. For more information, 
-- see the file "LICENSE.txt", which is included in the distribution.
-----------------------------------------------------------------------------
-- |
-- Maintainer  :  alex.gerdes@ou.nl
-- Stability   :  provisional
-- Portability :  unknown
--
-- Show the details of a service request. The input argument `id' should
-- correspond to record from the log database.
--
-----------------------------------------------------------------------------
module Main where

import Control.Monad
import Control.Monad.Trans
import Data.Char (toUpper)
import Data.List
import Data.Map hiding (null, map, (!))
import qualified Data.Map as DM
import Data.Maybe
import Database.HDBC
import Database.HDBC.Sqlite3 (connectSqlite3)
import Network.CGI
import Prelude hiding (lookup)
import System.Environment (getArgs)
import System.Posix.Env
import Text.XHtml

type Row = Map String SqlValue
type Rows = [Row]

-- | Settings
dbLocation = "service.db"
cgiName    = "query.cgi"

-- | Main program
main :: IO ()
main = do
  q <- getEnv "QUERY_STRING"
  when (isNothing q) $ do
    args <- getArgs        -- the cgi binary can be run from the command line, e.g. ./query.cgi page=last
    setEnv "QUERY_STRING" (intercalate "&" args) True
  runCGI $ handleErrors $ do
    reply <- processRequest
    output $ renderHtml reply

-- | Retrieve input parameters, query the db and process a HTML page
processRequest :: CGIT IO Html
processRequest = do
  page <- getInput' "page"  
  case page of
    "request" -> do 
      id  <- getInput' "id"
      row <- requestQuery id
      return $ requestPage row
    "last" -> do
      rows <- lastQuery
      return $ lastPage rows
    "all" -> do
      rows <- allQuery
      return $ allPage rows
    "frequency" -> do
      rows <- freqQuery
      return $ freqPage rows
    "query" -> do
      sql  <- getInput' "query"
      rows <- query sql
      return $ tablePage "Custom query" "" rows
    _ -> return mainPage

-- | Queries         
requestQuery id = do 
  (r:_) <- query $ "SELECT * FROM log WHERE id = " ++ id ++ ";"
  return r
lastQuery = query $ "SELECT id, service, exerciseID, source, dataformat, "
                 ++        "encoding, ipaddress, time, responsetime "
                 ++ "FROM log ORDER BY time DESC LIMIT 10;"
allQuery = query $ "SELECT id, service, exerciseID, source, dataformat, "
                ++        "encoding, ipaddress, time, responsetime "
                ++ "FROM log;"
freqQuery = query $ "SELECT DISTINCT source, exerciseID, service, "
                 ++                 "avg(responsetime), min(responsetime), "
                 ++                 "max(responsetime), count(source) "
                 ++ "FROM log GROUP BY source, exerciseID, service;"

-- | Web pages
requestPage :: Row -> Html 
requestPage row =  body << h1 << "Request"
               +++ myTable cells
               +++ paras
  where
    (cs, ps) = partitionWithKey (\k _ -> k /= "input" && k /= "output") row
    paras = let p title txt = h1 << capiFst title +++ pre << txt 
            in  foldWithKey (\c -> (+++) . p c) noHtml ps
    cells = foldWithKey (\c v -> (:) [bold (toHtml c), toHtml v]) [] cs

lastPage = tablePage "Service calls"
                     (  "The table show all service calls, with its details, "
                     ++ "from the last month. You can click on the service name "
                     ++ "to see the corresponding in- and output. You can also "
                     ++ "view some statistics of the service calls.")

allPage = tablePage "Service calls"
                     (  "The table show all service calls, with its details. "
                     ++ "You can click on the service name "
                     ++ "to see the corresponding in- and output. You can also "
                     ++ "view some statistics of the service calls.")

freqPage :: Rows -> Html
freqPage rows =  body << h1 << "Service statistics"
             +++ p << (  "The table shows how frequent a service call is made. You "
                      ++ "can also view all service calls of the last month.")
             +++ myTable (header : cells)
             +++ back
  where
    header = map (bold . toHtml) [ "Source", "ExerciseID", "Service"
                                 , "Average resp. time", "Min. resp. time"
                                 , "Max. resp. time", "Count" ]
    cells  = map (map toHtml . elems) rows

mainPage :: Html
mainPage =  body << h1 << "Ideas Log Analysis" 
        +++ p << (  "You can view a number of predefined queries on the log database, "
                 ++ "by clicking on one of the links below.")
        +++ unordList (let link page = hotlink (cgiName ++ "?page=" ++ page) << page
                       in  map link ["last", "all", "frequency"])
        +++ p << (  "You can also perform a custom query. " 
                 ++ "For example: select id from log")
        +++ guiGet cgiName << (  hidden "page" "query"
                             +++ textfield "query"
                             +++ submit "submit" "Run query"
                              )

-- | Help functions
getInput' :: String -> CGIT IO String
getInput' name = do
  raw <- getInput name
  case raw of
    Nothing -> fail $ "You did not specify the input parameter: " ++ name
    Just s  -> return s

query :: MonadTrans t => String -> t IO Rows
query q = lift $ do 
  conn <- connectSqlite3 dbLocation
  stmt <- prepare conn q
  execute stmt []
  rows <- fetchAllRowsMap' stmt -- uses the strict version for getting the results
  when (null rows) $ fail $ "The query `" ++ q ++ "', did not return any results."
  commit conn >> disconnect conn
  return rows

tablePage :: String -> String -> Rows ->  Html
tablePage title msg rows =  body << h1 << title +++ p << msg 
                        +++ myTable (header:cells) +++ back
  where
    header = map (bold . toHtml . capiFst) $ keys $ head rows
    cells  = map (elems . linkId . DM.map toHtml) rows
    linkId = let f id = Just $ toHtml $ self ("request&id=" ++ show id) << show id
             in update f "id"
	
instance HTML SqlValue where
  toHtml SqlNull = noHtml
  toHtml v = toHtml (fromSql v :: String)

capiFst :: String -> String
capiFst (c:cs) = toUpper c : cs
capiFst []      = []

myTable = simpleTable [border 1, cellpadding 5] []
back = br +++ self "main" << "Go back to the main page."
guiGet act = form ! [action act, method "GET"]
self page = hotlink (cgiName ++ "?page=" ++ page)