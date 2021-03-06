{-# LANGUAGE ScopedTypeVariables #-}
module Development.Ecstatic.Annotate where

import Development.Ecstatic.Utils
import Development.Ecstatic.StackUsage

import Language.C
import Language.C.Pretty
import Language.C.Data.Ident
import Language.C.Analysis
import Data.Generics.Uniplate.Data
import Data.Typeable
import Data.Data
import Data.Maybe
import Data.List (find)
import qualified Data.Map as M
import System.Console.ANSI
import Control.Monad
import Text.Printf
import Debug.Trace
import Control.Applicative
import qualified Text.PrettyPrint as PP

type CFile = String
type Line = Int

annotate :: CFile -> [FunDef] -> (FunDef -> Maybe String) -> CFile
annotate file fs op =
  let as = sortWith fst $ mapMaybe annotation fs
      file' = concatMap (attach as) (zip [1..] (lines file))
  in
    unlines $ file'
  where
    annotation :: FunDef -> Maybe (Line, String)
    annotation f@(FunDef _ _ nodeInfo) = do
      str <- op f
      let l = posRow . posOfNode $ nodeInfo
      return (l, str)

    attach as (num, line) =
      case lookup num as of
        Nothing -> [line]
        Just str -> [str, line]

runAnnotate :: FilePath -> FilePath -> (GlobalDecls -> FunDef -> Maybe String)
            -> IO ()
runAnnotate input output op =
  if input == output then
    putStrLn "Need distinct output file" else do

    ast <- parseFile input
    file <- readFile input
    let fs = parseAST ast

    case fs of
      Left errors -> do
        putStrLn "error:"
        mapM_ print errors
      Right (globals, fs)  -> do
        let file' = annotate file fs (op globals)
        writeFile output file'

nameNode (FunDef (VarDecl (VarName (Ident name' _ _) _) attrs tp) stmt node) =
  Just (name', node)
nameNode _ = Nothing

findDef :: [FunDef] -> String -> Maybe FunDef
findDef fns name =
  find match fns 
 where
   match def =
    case nameNode def of
      Nothing -> False
      Just (name', _) -> name' == name

stackAnn :: FilePath -> GlobalDecls -> FunDef -> Maybe String
stackAnn fname globals (FunDef (VarDecl (VarName (Ident name _ _) _) attrs tp) s info) =
  do fname' <- fileOfNode info
     if fname == fname' then
       Just . (("// stack usage " ++ name ++ ":\n// ") ++)
            . PP.render . pretty
            $ stackUsage globals s 
     else
       Nothing

doStackAnnotation :: FilePath -> IO ()
doStackAnnotation fname =
  runAnnotate fname (fname ++ ".out.c") (stackAnn fname)
