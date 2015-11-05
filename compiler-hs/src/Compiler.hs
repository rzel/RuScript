{-# LANGUAGE FlexibleContexts #-}

module Compiler where

import Parser
import Control.Applicative ((<|>))
import Control.Monad.RWS
import Control.Monad.Except
import qualified Data.Map as M
import Control.Monad
import NameSpace

-- XXX: Maybe some debug info ... like line number, can be forged into the monad stack

data SCode = SPushL Int
           | SPushG Int
           | SPopG Int
           | SAdd
           | SCall Int String Int
           | SRet
           | SNew Int
           | SPushInt Int
           | SPushStr String
           | SFrameEnd
           | SClass Int Int
           | SPrint
           | SPopL Int
           | SPopA Int
           | SPushA Int
           | SPushSelf
           deriving (Show, Eq)

type Config = ()

data Scope = Scope {
  globals        :: NameSpace,
  locals         :: Maybe NameSpace,
  classes        :: NameSpace,
  visibleGlobals :: Maybe [String],
  classScope     :: Maybe (M.Map String Int)
} deriving (Show)

initConfig = ()

initScope = Scope {
  globals = initNameSpace,
  locals  = Nothing,
  classes = initNameSpace,
  visibleGlobals = Nothing,
  classScope = Nothing
}

type Compiler = ExceptT String (RWS Config [SCode] Scope)

runCompiler src = runRWS (runExceptT (compile src)) initConfig initScope

compile :: Source -> Compiler ()
compile [] = return ()
compile (s:ss) = case s of
  Assignment lhs expr -> withGlobals lhs $ \i -> do
        pushExpr expr
        emit $ SPopG i
        compile ss
  ClassDecl name attrs methods -> withClasses name $ \i -> do
        emit $ SClass (length attrs) (length methods)
        tell (map SPushStr attrs)
        let classScope = M.fromList $ zip (attrs ++ map getMethodName methods) [0..]
        enterClassScope classScope $ mapM_ emitMethod methods
        compile ss
  Print expr -> do
        pushExpr expr
        emit SPrint
        compile ss
  Return expr -> ifInMethod $ do
        pushExpr expr
        emit SRet
        compile ss

-- stack top should reside the computed value
pushExpr :: Expr -> Compiler ()
pushExpr (Single tm) = pushTerm tm
pushExpr (Plus tm1 tm2) = do
    pushTerm tm1
    pushTerm tm2
    emit SAdd

pushTerm tm = case tm of
    Var x    -> pushVar x
    LitInt i -> emit $ SPushInt i
    LitStr s -> emit $ SPushStr s
    New className -> withClasses className $ emit . SNew
    call@(Call _ _ _) -> compileCall call
    acc@(Access _ _)  -> compileAccess acc

-- FIXME: PLEASE Consider self recursion
compileCall (Call receiver method params) = withGlobals receiver $ \recvi -> do
    enterMethod $ do
      mapM_ pushExpr params
      emit $ SCall recvi method $ length params

-- FIXME: Current ClassScope is too coarse, should split out attrs and methods one day (or not?)
compileAccess (Access "self" accessor) = inClass $ \cs -> do
    case M.lookup accessor cs of
        Just i  -> do
          emit SPushSelf  -- Push self on top of stack
          emit $ SPushA i -- Push attrs[i] of stacktop on top of stack
        Nothing -> throwError $ accessor ++ " is not defined as attributes" 

compileAccess (Access receiver accessor) = do
    pushVar receiver
    emit $ SPushAStr accessor

withGlobals :: String -> (Int -> Compiler ()) -> Compiler ()
withGlobals name f = do
    glbs <- globals <$> get
    case lookupName name glbs of
        Just i  -> f i
        Nothing -> addGlobal name >>= f

withClasses :: String -> (Int -> Compiler ()) -> Compiler ()
withClasses name f = do
    clss <- classes <$> get
    case lookupName name clss of
        Just i  -> f i
        Nothing -> addClass name >>= f

-- Shadowing Rule: Global > Local
emitMethod :: MethodDecl -> Compiler ()
emitMethod (MethodDecl name args glbs src) = inClass $ \_ -> do
    enterMethod $ do
      addVisibleGlobals glbs
      mapM_ addLocal args
      compile src
    emit $ SFrameEnd
    emit $ SPushStr name


emit :: SCode -> Compiler ()
emit x = tell [x]

pushVar x = do
  g <- pushGlobal x
  l <- pushLocal x
  case (g <|> l) of
    Nothing -> throwError $ "Can't find " ++ x ++ " in scope"
    Just inst -> emit inst

pushGlobal x = do
  glbs <- globals <$> get
  case lookupName x glbs of
      Just i  -> return $ Just $ SPushG i
      Nothing -> return Nothing

pushLocal x = do
  m <- locals <$> get
  case m of
    Just lcs -> case lookupName x lcs of
        Just i  -> return $ Just $ SPushL i
        Nothing -> return Nothing
    Nothing  -> return Nothing

addVisibleGlobals glbs = modify $ \scope -> scope { visibleGlobals = f (visibleGlobals scope) }
  where
    f Nothing = Just glbs
    f (Just gs) = Just (gs ++ glbs)

addLocal :: String -> Compiler Int
addLocal name = do
  scope <- get
  let Just l = locals scope
  let (l', nid) = insertName name l
  put $ scope { locals = Just l'}
  return nid

addGlobal :: String -> Compiler Int
addGlobal name = do
  scope <- get
  let (g', nid) = insertName name $ globals scope
  put $ scope { globals = g'}
  return nid

addAnonyLocal :: Compiler Int
addAnonyLocal = do
  scope <- get
  let Just l = locals scope
  let (l', nid) = insertAnony l
  put $ scope { locals = Just l'}
  return nid


addClass :: String -> Compiler Int
addClass name = do
  scope <- get
  let (c', nid) = insertName name $ classes scope
  put $ scope { classes = c'}
  return nid

-- Scoping Helpers

enterMethod f = do
  maybeLocals <- locals <$> get
  if maybeLocals == Nothing then do
    modify $ \scope -> scope { locals = Just initNameSpace, visibleGlobals = Just [] }
    f
    modify $ \scope -> scope { locals = Nothing, visibleGlobals = Nothing }
    else f


enterClassScope cs f = do
  modify $ \scope -> scope { classScope = Just cs }
  f
  modify $ \scope -> scope { classScope = Nothing }


inClass :: (M.Map String Int -> Compiler ()) -> Compiler ()
inClass f = do
  maybeCS <- classScope <$> get
  case maybeCS of
    Just cs -> f cs
    Nothing -> throwError "Not in class definition scope"


ifInMethod :: Compiler () -> Compiler ()
ifInMethod f = do
  maybeLocals <- locals <$> get
  if maybeLocals /= Nothing
    then f
    else throwError "Not in method scope"
