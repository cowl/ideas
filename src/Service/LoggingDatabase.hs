{-# OPTIONS -cpp #-}
-----------------------------------------------------------------------------
-- Copyright 2008, Open Universiteit Nederland. This file is distributed 
-- under the terms of the GNU General Public License. For more information, 
-- see the file "LICENSE.txt", which is included in the distribution.
-----------------------------------------------------------------------------
-- |
-- Maintainer  :  bastiaan.heeren@ou.nl
-- Stability   :  provisional
-- Portability :  portable (depends on ghc)
--
-- Facilities to create a log database
--
-----------------------------------------------------------------------------
module Service.LoggingDatabase where

import Data.Time
import Data.Maybe
import Service.Request
#ifndef DB
import Database.HDBC
import Database.HDBC.Sqlite3 (connectSqlite3)

logMessage :: Request -> String -> String -> String -> UTCTime -> IO ()
logMessage req input output ipaddress begin =
  do -- make a connection with the database
     conn <- connectSqlite3 "service.db"

     -- check if the database exists, if not make one
     tables <- getTables conn
     if not (elem "log" tables) then run conn createStmt [] else return 0

     -- calculate duration
     end <- getCurrentTime
     let diff = diffUTCTime end begin 

     -- insert data into database
     run conn logStmt [ toSql $ service req
                      , toSql $ show (exerciseID req)
                      , toSql $ fromMaybe "" (source req)
                      , toSql $ show (dataformat req)
                      , toSql $ maybe "unknown" show (encoding req)
                      , toSql $ input
                      , toSql $ output
                      , toSql $ ipaddress
                      , toSql $ begin
                      , toSql $ diff
                      ]
     commit conn

     -- close the connection to the database
     disconnect conn
       where
         logStmt    = "INSERT INTO log VALUES (?,?,?,?,?,?,?,?,?,?)"
         createStmt =  "CREATE TABLE log ( service      VARCHAR(250)"
                    ++                  ", exerciseID   VARCHAR(250)"
                    ++                  ", source       VARCHAR(250)"
                    ++                  ", dataformat   VARCHAR(250)"
                    ++                  ", encoding     VARCHAR(250)"
                    ++                  ", input        VARCHAR(250)"
                    ++                  ", output       VARCHAR(250)"
                    ++                  ", ipaddress    VARCHAR(20)"
                    ++                  ", time         TIME"
                    ++                  ", responsetime TIME"
#else
logMessage :: Request -> String -> String -> String -> UTCTime -> IO ()
logMessage _ _ _ _ _ = return ()
#endif

