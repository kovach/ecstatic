{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE StandaloneDeriving #-}
module Development.Ecstatic.Utils
where
import Development.Ecstatic.SimplifyDef
import Language.C
import Language.C.Data.Ident
import Language.C.System.GCC
import Language.C.Analysis
import Language.C.System.Preprocess (rawCppArgs, runPreprocessor)
import Data.Generics.Uniplate.Data
import Data.Typeable
import Data.Data
import Data.List

includeFlags :: FilePath -> [FilePath]
includeFlags base = [
  "-nostdinc",
  "-I./mocks/",

  "-I" ++ base ++ "/libswiftnav/include/libswiftnav",
  "-I" ++ base ++ "/libswiftnav/include/",
  "-I" ++ base ++ "/libopencm3/include/",

  "-I" ++ base ++ "/ChibiOS-RT/os/kernel/include/",
  "-I" ++ base ++ "/ChibiOS-RT/os/ports/GCC/ARMCMx/",
  "-I" ++ base ++ "/ChibiOS-RT/os/ports/GCC/ARMCMx/STM32F4xx/",
  "-I" ++ base ++ "/ChibiOS-RT/os/ports/common/ARMCMx/",

  "-I" ++ base ++ "/libsbp/c/include/",
  "-I" ++ base ++ "/libsbp/c/src",

  "-I" ++ base ++ "/libswiftnav/src",
  "-I" ++ base ++ "/libswiftnav/clapack-3.2.1-CMAKE/INCLUDE",
  "-I" ++ base ++ "/libswiftnav/CBLAS/include",

  "-I" ++ base ++ "/src",

  "-mno-sse3"
  ]

-- General Stuff
mapFst :: (a -> b) -> (a, c) -> (b, c)
mapFst f (a, b) = (f a, b)
mapSnd :: (a -> b) -> (c, a) -> (c, b)
mapSnd f (a, b) = (a, f b)

sortWith :: Ord b => (a -> b) -> [a] -> [a]
sortWith f = sortBy (\x y -> compare (f x) (f y))

-- Substitution functions --

-- Substitute a variable for an expression throughout anything that contains
-- expressions (e.g. AST, CExpression, CStatement)
substitute :: forall a b . (Data a, Typeable a, Data b, Typeable b) =>
                Ident -> CExpression b -> a -> a
substitute i e = transformBi f
  where f :: CExpression b -> CExpression b
        f v@(CVar i' _) = if i == i' then e else v
        f x = x

-- Substitute any variable matching a given name for an expression throughout
-- anything that contains expressions (e.g. AST, CExpression, CStatement)
subByName :: forall a b . (Data a, Typeable a, Data b, Typeable b)
          => String -> CExpression b -> a -> a
subByName n e = transformBi f
  where f :: CExpression b -> CExpression b
        f v@(CVar (Ident s _ _) _) = if n == s then e else v
        f x = x

isMaxCall :: CExpr -> Maybe [CExpr]
isMaxCall (CCall (CVar (Ident "_max" _ _) _) args _) = Just args
isMaxCall _ = Nothing
isCond :: CExpr -> Maybe (CExpr, CExpr, CExpr, CExpr) 
isCond (CCond (CBinary CGrOp l r _) (Just t) e _) = Just (l,r,t,e)
isCond _ = Nothing

-- TODO remove this!!
-- it will cause bugs
subAllNames :: CExpr -> CExpr -> CExpr
subAllNames e = transformBi f
  where
   f :: CExpr -> CExpr
   f x | Just _ <- isCond x = x
   f x@(CBinary _ _ _ _) = x
   f x | Just _ <- isMaxCall x = x
   f x@(CVar (Ident "_max" _ _) _) = x
   f x | Just _ <- isAtom x = e -- trace ("\nsee: " ++ show x++"\n") $ e
   f x = x

-- Reduces 'MAX' instances
reduceCond :: CExpr -> CExpr
reduceCond expr
  | Just args <- isMaxCall expr
  , Just vals <- mapM isPrim args
  = fromIntegral $ maximum (0:vals)
reduceCond expr
  | Just (l,r,t,e) <- isCond expr
  , Just lval <- isPrim l
  , Just rval <- isPrim r =
      if lval > rval
      then t
      else e
reduceCond e = e

reduceConditionals :: CExpr -> CExpr
reduceConditionals = transformBi reduceCond

-- List identifiers in term
getIdentifiers :: CExpr -> [(String, NodeInfo)]
getIdentifiers expr = [(name, node) | (Ident name _ node) <- universeBi expr]

-- Parsing Stuff --
checkResult :: (Show a) => String -> (Either a b) -> IO b
checkResult label = either (error . (label++) . show) return

parseFile :: FilePath -> FilePath -> IO CTranslUnit
parseFile base input_file =
  do parse_result <- parseCFile (newGCC "gcc") Nothing (includeFlags base) input_file
     checkResult "[Parsing]" parse_result

preprocessFile :: FilePath -> FilePath -> IO String
preprocessFile base file = do
  out <- runPreprocessor (newGCC "gcc") (rawCppArgs (includeFlags base) file)
  case out of
    Left code -> return $ show code
    Right stream -> return $ inputStreamToString stream

extractFuncs :: DeclEvent -> Trav [FunDef] ()
extractFuncs (DeclEvent (FunctionDef f)) = do
  modifyUserState (\x -> f:x)
  return ()
extractFuncs _ = return ()

parseAST :: CTranslUnit -> Either [CError] (GlobalDecls, [FunDef])
parseAST ast = do
  (globals, funcs) <- runTrav [] $ withExtDeclHandler (analyseAST ast) extractFuncs
  return $ (globals, userState funcs)

parseASTFiles :: FilePath -> [FilePath] -> IO (Maybe (GlobalDecls, [FunDef]))
parseASTFiles _ [] = do
  putStrLn "parseFiles requires at least one file"
  return Nothing
parseASTFiles base files = do
  asts <- mapM (parseFile base) files
  case mapM parseAST asts of
    Left err -> do putStrLn $ "bad ast: " ++ show err
                   return Nothing
    Right pairs ->
      let (globals, fns) = unzip pairs
      in
        return $ Just (foldr1 mergeGlobalDecls globals, concat fns)

-- TODO only used for error reporting/debugging; remove?
deriving instance Show EnumTypeRef
deriving instance Show CompTypeRef
deriving instance Show VarName
deriving instance Show BuiltinType
deriving instance Show DeclAttrs
deriving instance Show TypeQuals
deriving instance Show TypeName
deriving instance Show VarDecl
deriving instance Show ParamDecl
deriving instance Show TypeDefRef
deriving instance Show FunType
deriving instance Show ArraySize
deriving instance Show Type
deriving instance Show Attr
deriving instance Show TypeDef
deriving instance Show ObjDef
deriving instance Show EnumType
deriving instance Show FunDef
deriving instance Show Enumerator
deriving instance Show Decl
deriving instance Show IdentDecl
deriving instance Show MemberDecl
deriving instance Show CompType
deriving instance Show TagDef

