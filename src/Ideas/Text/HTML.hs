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
-- A minimal interface for constructing simple HTML pages
-- See http://www.w3.org/TR/html4/
--
-----------------------------------------------------------------------------

module Ideas.Text.HTML
   ( ToHTML(..), HTMLPage, HTMLBuilder
   , addCSS, addScript, addStyle, showHTML
   , string, text
   , htmlPage, link
   , h1, h2, h3, h4, h5, h6
   , preText, ul, table, keyValueTable
   , image, space, spaces, (<#>), spaced
   , highlightXML
   , para, ttText, hr, br, pre, bullet
   , divClass, spanClass
     -- HTML generic attributes
   , idA, classA, styleA, titleA
     -- Font style elements
   , tt, italic, bold, big, small
   , module Data.Monoid
   ) where

import Data.Char
import Data.List
import Data.Monoid hiding ((<>))
import Ideas.Text.XML
import Prelude hiding (div)
import qualified Ideas.Text.XML as XML
import qualified Data.Map as M

type HTMLBuilder = XMLBuilder

class ToHTML a where
   toHTML     :: a -> HTMLBuilder
   listToHTML :: [a] -> HTMLBuilder
   -- default definitions
   listToHTML = ul . map toHTML

instance ToHTML a => ToHTML [a] where
   toHTML = listToHTML

instance (ToHTML a, ToHTML b) => ToHTML (Either a b) where
   toHTML = either toHTML toHTML

instance (ToHTML a) => ToHTML (Maybe a) where
   toHTML = maybe mempty toHTML

instance ToHTML () where
   toHTML _ = mempty

instance (ToHTML a, ToHTML b) => ToHTML (a, b) where
   toHTML (a, b) = toHTML a <#> toHTML b
 
instance (ToHTML a, ToHTML b, ToHTML c) => ToHTML (a, b, c) where
   toHTML (a, b, c) = toHTML a <#> toHTML b <#> toHTML c

instance (ToHTML a, ToHTML b) => ToHTML (M.Map a b) where
   toHTML = Ideas.Text.HTML.table False . map f . M.toList
    where
      f (a, b) = [toHTML a, toHTML b]

instance ToHTML Int where
   toHTML = text

instance ToHTML Bool where
   toHTML = text

instance ToHTML Char where
   toHTML     = string . return
   listToHTML = string

data HTMLPage = HTMLPage
   { title       :: String
   , styleSheets :: [FilePath]
   , scripts     :: [FilePath]
   , styleTxts   :: [String]
   , htmlContent :: HTMLBuilder
   }

instance ToXML HTMLPage where
   toXML page = makeXML "html" $
      element "head"
         [ tag "title" (string (title page))
         , mconcat
              [ element "link"
                   [ "rel"  .=. "STYLESHEET"
                   , "href" .=. css
                   , "type" .=. "text/css"
                   ]
              | css <- styleSheets page
              ]
         , mconcat
              [ tag "style" (unescaped txt)
              | txt <- styleTxts page
              ]
         , mconcat
              [ element "script" ["src" .=. js, "type" .=. "text/javascript", string " "]
              | js <- scripts page
              ]
         ]
      <> tag "body" (htmlContent page)

showHTML :: HTMLPage -> String
showHTML = compactXML . toXML

addCSS :: FilePath -> HTMLPage -> HTMLPage
addCSS css page = page { styleSheets = css : styleSheets page }

addScript :: FilePath -> HTMLPage -> HTMLPage
addScript js page = page { scripts = js : scripts page }

addStyle :: String -> HTMLPage -> HTMLPage
addStyle txt page = page { styleTxts = txt : styleTxts page }

-- html helper functions
htmlPage :: String -> HTMLBuilder -> HTMLPage
htmlPage s = HTMLPage s [] [] []

link :: BuildXML a => String -> a -> a
link url body = tag "a" $
   ("href" .=. url) <> body

h1, h2, h3, h4, h5, h6 :: BuildXML a => String -> a
h1 = tag "h1" . string
h2 = tag "h2" . string
h3 = tag "h3" . string
h4 = tag "h4" . string
h5 = tag "h5" . string
h6 = tag "h6" . string

para :: BuildXML a => a -> a
para = tag "p"

preText :: BuildXML a => String -> a
preText = pre . string

pre :: BuildXML a => a -> a
pre = tag "pre"

hr :: BuildXML a => a
hr = emptyTag "hr"

br :: BuildXML a => a
br = emptyTag "br"

ttText :: BuildXML a => String -> a
ttText = tt . string

ul :: BuildXML a => [a] -> a
ul xs 
   | null xs   = mempty
   | otherwise = element "ul" (map (tag "li") xs)

-- | First argument indicates whether the table has a header or not
table :: BuildXML a => Bool -> [[a]] -> a
table b rows 
   | null rows = mempty
   | otherwise = element "table" $
        ("border" .=. "1") :
        [ element "tr" $
             ("class" .=. getClass i) :
             [ tag "td" c | c <- row ]
        | (i, row) <- zip [0::Int ..] rows
        ]
 where
   getClass i
      | i == 0 && b = "top-row"
      | even i      = "even-row"
      | otherwise   = "odd-row"

keyValueTable :: BuildXML a => [(String, a)] -> a
keyValueTable =
   let f (s, a) = [spanClass "table-key" (string s), a]
   in para . table False . map f

spaces :: BuildXML a => Int -> a
spaces n = mconcat (replicate n space)

space, bullet :: BuildXML a => a
space  = XML.unescaped "&nbsp;"
bullet = XML.unescaped "&#8226;"

(<#>) :: BuildXML a => a -> a -> a
x <#> y = x <> space <> y

spaced :: BuildXML a => [a] -> a
spaced = mconcat . intersperse space

image :: BuildXML a => String -> a
image n = tag "img" ("src" .=. n)

divClass :: BuildXML a =>  String -> a -> a
divClass n a = tag "div" (classA n <> a)

spanClass :: BuildXML a =>  String -> a -> a
spanClass n a = tag "span" (classA n <> a)

-- A simple XML highlighter
highlightXML :: Bool -> XML -> HTMLBuilder
highlightXML nice
   | nice      = builder . highlight . makeXML "pre" . string . show
   | otherwise = builder . highlight . makeXML "tt"  . string . compactXML
 where
   highlight :: XML -> XML
   highlight html = html {content = map (either (Left . f) Right) (content html)}

   -- find <
   f :: String -> String
   f [] = []
   f list@(x:xs)
      | "&lt;/" `isPrefixOf` list = -- close tag
           let (as, bs) = span isAlphaNum (drop 5 list)
           in "<font color='blue'>&lt;/" ++ as ++ "<font color='green'>" ++ g bs
      | "&lt;" `isPrefixOf` list = -- open tag
           let (as, bs) = span isAlphaNum (drop 4 list)
           in "<font color='blue'>&lt;" ++ as ++ "<font color='green'>" ++ g bs
      | otherwise = x : f xs
   -- find >
   g [] = []
   g list@(x:xs)
      | "/&gt;" `isPrefixOf` list =
           "</font>/&gt;</font>" ++ f (drop 5 list)
      | "&gt;" `isPrefixOf` list =
           "</font>&gt;</font>" ++ f (drop 4 list)
      | x=='=' = "<font color='orange'>=</font>" ++ g xs
      | otherwise = x : g xs

-----------------------------------------------------------
-- * HTML generic attributes

idA, classA, styleA, titleA :: BuildXML a => String -> a
idA    = ("id"     .=.)  -- document-wide unique id
classA = ("class"  .=.)  -- space-separated list of classes
styleA = ("style"  .=.)  -- associated style info
titleA = ("title"  .=.)  -- advisory title

-----------------------------------------------------------
-- * Font style elements

-- | Renders as teletype or monospaced Ideas.Text.
tt :: BuildXML a => a -> a
tt = tag "tt"

-- | Renders as italic text style.
italic :: BuildXML a => a -> a
italic = tag "i"

-- | Renders as bold text style.
bold :: BuildXML a => a -> a
bold = tag "b"

-- BIG: Renders text in a "large" font.
big :: BuildXML a => a -> a
big = tag "big"

-- SMALL: Renders text in a "small" font.
small :: BuildXML a => a -> a
small = tag "small"