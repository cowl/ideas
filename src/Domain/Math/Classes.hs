module Domain.Math.Classes where

import Common.Uniplate

class Symbolic a where
   variable   :: String -> a
   symbol     :: String -> a
   function   :: String -> [a] -> a
   -- default definition
   symbol s = function s []

unaryFunction :: Symbolic a => String -> a -> a
unaryFunction f a = function f [a]

binaryFunction :: Symbolic a => String -> a -> a -> a
binaryFunction f a b = function f [a, b] 
   
class NF a where
   normalize :: a -> a