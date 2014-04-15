{-# LANGUAGE FlexibleInstances #-}
-- | This module provides various simple ways to query and manipulate
-- fundamental Futhark terms, such as types and values.  The intent is to
-- keep "Futhark.Language.Syntax" simple, and put whatever embellishments
-- we need here.
module Language.Futhark.Attributes
  (
    TypeBox(..)
  , funDecByName
  , progNames

  -- * Parameter handling
  , toParam
  , fromParam

  -- * Queries on expressions
  , expToValue
  , mapTails
  , typeOf
  , freeInExp
  , freeNamesInExp

  -- * Queries on patterns
  , patNames
  , patNameSet
  , patIdents
  , patIdentSet

  -- * Queries on types
  , basicType
  , uniqueness
  , unique
  , uniqueOrBasic
  , aliases
  , diet
  , dietingAs
  , subtypeOf
  , similarTo
  , arrayRank
  , arrayDims
  , setArrayDims
  , returnType
  , lambdaType
  , lambdaReturnType

  -- * Operations on types
  , stripArray
  , peelArray
  , arrayOf
  , arrayType
  , elemType
  , rowType
  , toDecl
  , toElemDecl
  , fromDecl
  , fromElemDecl
  , setAliases
  , setElemAliases
  , addAliases
  , addElemAliases
  , setUniqueness
  , unifyUniqueness

  -- ** Removing and adding names
  --
  -- $names
  , addNames
  , addElemNames
  , removeNames
  , removeElemNames

  -- * Queries on values
  , arrayString
  , valueType

  -- * Operations on values
  , arrayVal
  , emptyArray

  -- * Type aliases

  -- | Values of these types are produces by the parser.  They use
  -- unadorned names and have no type information, apart from that
  -- which is syntactically required.
  , NoInfo(..)
  , UncheckedType
  , UncheckedIdent
  , UncheckedExp
  , UncheckedLambda
  , UncheckedTupIdent
  , UncheckedFunDec
  , UncheckedProg
  )
  where

import Control.Applicative
import Control.Monad.Writer

import Data.Array
import Data.Hashable
import Data.List
import Data.Maybe
import qualified Data.HashSet as HS

import Language.Futhark.Syntax
import Language.Futhark.Traversals

-- | Return the dimensionality of a type.  For non-arrays, this is
-- zero.  For a one-dimensional array it is one, for a two-dimensional
-- it is two, and so forth.
arrayRank :: TypeBase vn as -> Int
arrayRank = length . arrayDims

-- | Return the dimensions of a type - for non-arrays, this is the
-- empty list.
arrayDims :: TypeBase vn as -> ArraySize as
arrayDims (Array _ ds _ _) = ds
arrayDims _                = []

-- | Set the dimensions of an array.  If the given type is not an
-- array, return the type unchanged.
setArrayDims :: ArraySize as -> TypeBase vn as -> TypeBase vn as
setArrayDims ds (Array et _ u as) = Array et ds u as
setArrayDims _  t                 = t

-- | @x `subuniqueOf` y@ is true if @x@ is not less unique than @y@.
subuniqueOf :: Uniqueness -> Uniqueness -> Bool
subuniqueOf Nonunique Unique = False
subuniqueOf _ _ = True

-- | @x \`subtypeOf\` y@ is true if @x@ is a subtype of @y@ (or equal to
-- @y@), meaning @x@ is valid whenever @y@ is.
subtypeOf :: TypeBase vn as1 -> TypeBase vn as2 -> Bool
subtypeOf (Array t1 dims1 u1 _) (Array t2 dims2 u2 _) =
  u1 `subuniqueOf` u2
       && Elem t1 `subtypeOf` Elem t2
       && length dims1 == length dims2
subtypeOf (Elem (Tuple ts1)) (Elem (Tuple ts2)) =
  length ts1 == length ts2 && and (zipWith subtypeOf ts1 ts2)
subtypeOf (Elem (Basic bt1)) (Elem (Basic bt2)) = bt1 == bt2
subtypeOf _ _ = False

-- | @x \`similarTo\` y@ is true if @x@ and @y@ are the same type,
-- ignoring uniqueness.
similarTo :: TypeBase vn as -> TypeBase vn as -> Bool
similarTo t1 t2 = t1 `subtypeOf` t2 || t2 `subtypeOf` t1

-- | Return the uniqueness of a type.
uniqueness :: TypeBase vn as -> Uniqueness
uniqueness (Array _ _ u _) = u
uniqueness _ = Nonunique

-- | @unique t@ is 'True' if the type of the argument is unique.
unique :: TypeBase vn as -> Bool
unique = (==Unique) . uniqueness

-- | Return the set of all variables mentioned in the aliasing of a
-- type.
aliases :: Monoid (as vn) => TypeBase as vn -> as vn
aliases (Array _ _ _ als) = als
aliases (Elem (Tuple et)) = mconcat $ map aliases et
aliases (Elem _)          = mempty

-- | @diet t@ returns a description of how a function parameter of
-- type @t@ might consume its argument.
diet :: TypeBase as vn -> Diet
diet (Elem (Tuple ets)) = TupleDiet $ map diet ets
diet (Elem _) = Observe
diet (Array _ _ Unique _) = Consume
diet (Array _ _ Nonunique _) = Observe

-- | @t `dietingAs` d@ modifies the uniqueness attributes of @t@ to
-- reflect how it is consumed according to @d@ - if it is consumed, it
-- becomes 'Unique'.  Tuples are handled intelligently.
dietingAs :: TypeBase as vn -> Diet -> TypeBase as vn
Elem (Tuple ets) `dietingAs` TupleDiet ds =
  Elem $ Tuple $ zipWith dietingAs ets ds
t `dietingAs` Consume =
  t `setUniqueness` Unique
t `dietingAs` _ =
  t `setUniqueness` Nonunique

-- | @t `maskAliases` d@ removes aliases (sets them to 'mempty') from
-- the parts of @t@ that are denoted as 'Consumed' by the 'Diet' @d@.
maskAliases :: Monoid (as vn) => TypeBase as vn -> Diet -> TypeBase as vn
maskAliases t Consume = t `setAliases` mempty
maskAliases t Observe = t
maskAliases (Elem (Tuple ets)) (TupleDiet ds) =
  Elem $ Tuple $ zipWith maskAliases ets ds
maskAliases _ _ = error "Invalid arguments passed to maskAliases."

-- | Remove aliasing information from a type.
toDecl :: TypeBase as vn -> DeclTypeBase vn
toDecl (Array et sz u _) = Array (toElemDecl et) sz u NoInfo
toDecl (Elem et) = Elem $ toElemDecl et

-- | Remove aliasing information from an element type.
toElemDecl :: ElemTypeBase as vn -> ElemTypeBase NoInfo vn
toElemDecl (Tuple ts) = Tuple $ map toDecl ts
toElemDecl t          = t `setElemAliases` NoInfo

-- | Replace no aliasing with an empty alias set.
fromDecl :: DeclTypeBase vn -> TypeBase Names vn
fromDecl (Array et sz u _) = Array et sz u HS.empty
fromDecl (Elem et) = Elem $ fromElemDecl et

-- | Replace no aliasing with an empty alias set.
fromElemDecl :: ElemTypeBase NoInfo vn -> ElemTypeBase Names vn
fromElemDecl (Tuple ts) = Tuple $ map fromDecl ts
fromElemDecl t          = t `setElemAliases` HS.empty

-- | A type box provides a way to box a 'CompTypeBase', and possibly
-- retrieve one, if the box is not empty.  This can be used to write
-- function on Futhark terms that are polymorphic in the type annotations,
-- yet can still inspect types if they are present.
class TypeBox ty where
  -- | Try to retrieve a type from the type box.
  unboxType :: ty vn -> Maybe (CompTypeBase vn)
  -- | Put a type in the box.
  boxType :: CompTypeBase vn -> ty vn
  -- | Apply a mapping action to the type contained in the box.
  mapType :: Applicative f =>
             (CompTypeBase vn -> f (CompTypeBase vn')) -> ty vn -> f (ty vn')

instance TypeBox NoInfo where
  unboxType = const Nothing
  boxType = const NoInfo
  mapType = const . const (pure NoInfo)

instance TypeBox CompTypeBase where
  unboxType = Just
  boxType = id
  mapType = ($)

instance TypeBox DeclTypeBase where
  unboxType = Just . fromDecl
  boxType = toDecl
  mapType f x = toDecl <$> f (fromDecl x)

-- | @peelArray n t@ returns the type resulting from peeling the first
-- @n@ array dimensions from @t@.  Returns @Nothing@ if @t@ has less
-- than @n@ dimensions.
peelArray :: Int -> TypeBase as vn -> Maybe (TypeBase as vn)
peelArray 0 t = Just t
peelArray 1 (Array et [_] _ als) = Just $ Elem et `setAliases` als
peelArray n (Array et (_:ds) u als) =
  peelArray (n-1) $ Array et ds u als
peelArray _ _ = Nothing

-- | Returns the bottommost type of an array.  For @[[int]]@, this
-- would be @int@.
elemType :: TypeBase vn as -> ElemTypeBase vn as
elemType (Array t _ _ als) = t `setElemAliases` als
elemType (Elem t) = t

-- | Return the immediate row-type of an array.  For @[[int]]@, this
-- would be @[int]@.
rowType :: TypeBase vn as -> TypeBase vn as
rowType = stripArray 1

-- | A type is a basic type if it is not an array and any component
-- types are basic types.
basicType :: TypeBase vn as -> Bool
basicType (Array {}) = False
basicType (Elem (Tuple ts)) = all basicType ts
basicType _ = True

-- | Is the given type either unique (as per 'unique') or basic (as
-- per 'basicType')?
uniqueOrBasic :: TypeBase vn as -> Bool
uniqueOrBasic x = basicType x || unique x

-- $names
--
-- The element type annotation of 'ArrayVal' values is a 'TypeBase'
-- with '()' for variable names.  This means that when we construct
-- 'ArrayVal's based on a type with a more common name representation,
-- we need to remove the names and replace them with '()'s.  Since the
-- only place names appear in types is in the array size annotations,
-- and those can always be replaced with 'Nothing', we can simply put
-- that in, instead of the original expression (if any).

-- | Remove names from a type - this involves removing all size
-- annotations from arrays, as well as all aliasing.
removeNames :: TypeBase as vn -> TypeBase NoInfo ()
removeNames (Array et sizes u _) =
  Array (removeElemNames et) (map (const Nothing) sizes) u NoInfo
removeNames (Elem et) = Elem $ removeElemNames et

-- | Remove names from an element type, as in 'removeNames'.
removeElemNames :: ElemTypeBase as vn -> ElemTypeBase NoInfo ()
removeElemNames (Tuple ets) = Tuple $ map removeNames ets
removeElemNames (Basic bt) = Basic bt

-- | Add names to a type - this replaces array sizes with 'Nothing',
-- although they probably are already, if you're using this.
addNames :: TypeBase NoInfo () -> TypeBase NoInfo vn
addNames (Array et sizes u _) =
  Array (addElemNames et) (map (const Nothing) sizes) u NoInfo
addNames (Elem et) = Elem $ addElemNames et

-- | Add names to an element type - this replaces array sizes with
-- 'Nothing', although they probably are already, if you're using
-- this.
addElemNames :: ElemTypeBase NoInfo () -> ElemTypeBase NoInfo vn
addElemNames (Tuple ets) = Tuple $ map addNames ets
addElemNames (Basic bt)  = Basic bt

-- | @arrayOf t s u@ constructs an array type.  The convenience
-- compared to using the 'Array' constructor directly is that @t@ can
-- itself be an array.  If @t@ is an @n@-dimensional array, and @s@ is
-- a list of length @n@, the resulting type is of an @n+m@ dimensions.
-- The uniqueness of the new array will be @u@, no matter the
-- uniqueness of @t@.
arrayOf :: Monoid (vn as) =>
           TypeBase vn as -> ArraySize as -> Uniqueness -> TypeBase vn as
arrayOf (Array et size1 _ als) size2 u =
  Array et (size2 ++ size1) u als
arrayOf (Elem et) size u =
  Array (et `setElemAliases` NoInfo) size u $ aliases $ Elem et

-- | @array n t@ is the type of @n@-dimensional arrays having @t@ as
-- the base type.  If @t@ is itself an m-dimensional array, the result
-- is an @n+m@-dimensional array with the same base type as @t@.  If
-- you need to specify size information for the array, use 'arrayOf'
-- instead.
arrayType :: Monoid (as vn) =>
             Int -> TypeBase as vn -> Uniqueness -> TypeBase as vn
arrayType 0 t _ = t
arrayType n t u = arrayOf t ds u
  where ds = replicate n Nothing

-- | @stripArray n t@ removes the @n@ outermost layers of the array.
-- Essentially, it is the type of indexing an array of type @t@ with
-- @n@ indexes.
stripArray :: Int -> TypeBase vn as -> TypeBase vn as
stripArray n (Array et ds u als)
  | n < length ds = Array et (drop n ds) u als
  | otherwise     = Elem et `setAliases` als
stripArray _ t = t

-- | Set the uniqueness attribute of a type.  If the type is a tuple,
-- the uniqueness of its components will be modified.
setUniqueness :: TypeBase as vn -> Uniqueness -> TypeBase as vn
setUniqueness (Array et dims _ als) u = Array et dims u als
setUniqueness (Elem (Tuple ets)) u =
  Elem $ Tuple $ map (`setUniqueness` u) ets
setUniqueness t _ = t

-- | @t \`setAliases\` als@ returns @t@, but with @als@ substituted for
-- any already present aliasing.
setAliases :: TypeBase asf vn -> ast vn -> TypeBase ast vn
setAliases t = addAliases t . const

-- | @t \`setElemAliases\` als@ returns @t@, but with @als@ substituted for
-- any already present aliasing.
setElemAliases :: ElemTypeBase asf vn -> ast vn -> ElemTypeBase ast vn
setElemAliases t = addElemAliases t . const

-- | @t \`addAliases\` f@ returns @t@, but with any already present
-- aliasing replaced by @f@ applied to that aliasing.
addAliases :: TypeBase asf vn -> (asf vn -> ast vn) -> TypeBase ast vn
addAliases (Array et dims u als) f = Array et dims u $ f als
addAliases (Elem et) f = Elem $ et `addElemAliases` f

-- | @t \`addAliases\` f@ returns @t@, but with any already present
-- aliasing replaced by @f@ applied to that aliasing.
addElemAliases :: ElemTypeBase asf vn -> (asf vn -> ast vn) -> ElemTypeBase ast vn
addElemAliases (Tuple ets) f = Tuple $ map (`addAliases` f) ets
addElemAliases (Basic bt) _ = Basic bt

-- | Unify the uniqueness attributes and aliasing information of two
-- types.  The two types must otherwise be identical.  The resulting
-- alias set will be the 'mappend' of the two input types aliasing sets,
-- and the uniqueness will be 'Unique' only if both of the input types
-- are unique.
unifyUniqueness :: Monoid (as vn) =>
                   TypeBase as vn -> TypeBase as vn -> TypeBase as vn
unifyUniqueness (Array et dims u1 als1) (Array _ _ u2 als2) =
  Array et dims (u1 <> u2) (als1 <> als2)
unifyUniqueness (Elem (Tuple ets1)) (Elem (Tuple ets2)) =
  Elem $ Tuple $ zipWith unifyUniqueness ets1 ets2
unifyUniqueness t1 _ = t1

-- | The type of an Futhark value.
valueType :: Value -> DeclTypeBase vn
valueType (BasicVal bv) = Elem $ Basic $ basicValueType bv
valueType (TupVal vs) = Elem $ Tuple (map valueType vs)
valueType (ArrayVal _ (Elem et)) =
  Array (addElemNames et) [Nothing] Nonunique NoInfo
valueType (ArrayVal _ (Array et ds _ _)) =
  Array (addElemNames et) (Nothing:replicate (length ds) Nothing) Nonunique NoInfo

-- | Construct an array value containing the given elements.
arrayVal :: [Value] -> TypeBase as vn -> Value
arrayVal vs = ArrayVal (listArray (0, length vs-1) vs) . removeNames . toDecl

-- | An empty array with the given row type.
emptyArray :: TypeBase as vn -> Value
emptyArray = arrayVal []

-- | If the given value is a nonempty array containing only
-- characters, return the corresponding 'String', otherwise return
-- 'Nothing'.
arrayString :: Value -> Maybe String
arrayString (ArrayVal arr _)
  | c:cs <- elems arr = mapM asChar $ c:cs
  where asChar (BasicVal (CharVal c)) = Just c
        asChar _                      = Nothing
arrayString _ = Nothing

-- | The type of an Futhark term.  The aliasing will refer to itself, if
-- the term is a non-tuple-typed variable.
typeOf :: (Eq vn, Hashable vn) => ExpBase CompTypeBase vn -> CompTypeBase vn
typeOf (Literal val _) = fromDecl $ valueType val
typeOf (TupLit es _) = Elem $ Tuple $ map typeOf es
typeOf (ArrayLit es t _) =
  arrayType 1 t $ mconcat $ map (uniqueness . typeOf) es
typeOf (BinOp _ _ _ t _) = t
typeOf (Not _ _) = Elem $ Basic Bool
typeOf (Negate e _) = typeOf e
typeOf (If _ _ _ t _) = t
typeOf (Var ident) =
  case identType ident of
    Elem (Tuple ets) -> Elem $ Tuple ets
    t                -> t `addAliases` HS.insert (identName ident)
typeOf (Apply _ _ t _) = t
typeOf (LetPat _ _ body _) = typeOf body
typeOf (LetWith _ _ _ _ _ _ body _) = typeOf body
typeOf (Index _ ident _ idx _) =
  stripArray (length idx) (identType ident)
  `addAliases` HS.insert (identName ident)
typeOf (Iota _ _) = arrayType 1 (Elem $ Basic Int) Unique
typeOf (Size {}) = Elem $ Basic Int
typeOf (Replicate _ e _) = arrayType 1 (typeOf e) u
  where u | uniqueOrBasic (typeOf e) = Unique
          | otherwise = Nonunique
typeOf (Reshape _ [] e _) =
  Elem $ elemType $ typeOf e
typeOf (Reshape _ shape  e _) =
  replicate (length shape) Nothing `setArrayDims` typeOf e
typeOf (Rearrange _ _ e _) = typeOf e
typeOf (Rotate _ _ e _) = typeOf e
typeOf (Transpose _ k n e _)
  | Array et dims u als <- typeOf e,
    (pre,d:post) <- splitAt k dims,
    (mid,end) <- splitAt n post = Array et (pre++mid++[d]++end) u als
  | otherwise = typeOf e
typeOf (Map f arr _) = arrayType 1 et $ uniqueProp et
  where et = lambdaType f [rowType $ typeOf arr]
typeOf (Reduce fun start arr _) =
  lambdaType fun [typeOf start, rowType (typeOf arr)]
typeOf (Zip es _) = arrayType 1 (Elem $ Tuple $ map snd es) Nonunique
typeOf (Unzip _ ts _) =
  Elem $ Tuple $ map (\t -> arrayType 1 t $ uniqueProp t) ts
typeOf (Scan fun start arr _) =
  arrayType 1 et Unique
    where et = lambdaType fun [typeOf start, rowType $ typeOf arr]
typeOf (Filter _ arr _) = typeOf arr
typeOf (Redomap outerfun innerfun start arr _) =
  lambdaType outerfun [innerres, innerres]
    where innerres = lambdaType innerfun [typeOf start, rowType $ typeOf arr]
typeOf (Split _ _ e _) =
  Elem $ Tuple [typeOf e, typeOf e]
typeOf (Concat _ x y _) = typeOf x `setUniqueness` u
  where u = uniqueness (typeOf x) <> uniqueness (typeOf y)
typeOf (Copy e _) = typeOf e `setUniqueness` Unique `setAliases` HS.empty
typeOf (Assert _ _) = Elem $ Basic Cert
typeOf (Conjoin _ _) = Elem $ Basic Cert
typeOf (DoLoop _ _ _ _ _ body _) = typeOf body

uniqueProp :: TypeBase vn as -> Uniqueness
uniqueProp tp = if uniqueOrBasic tp then Unique else Nonunique

-- | If possible, convert an expression to a value.  This is not a
-- true constant propagator, but a quick way to convert array/tuple
-- literal expressions into literal values instead.
expToValue :: ExpBase (TypeBase as) vn -> Maybe Value
expToValue (Literal val _) = Just val
expToValue (TupLit es _) = do es' <- mapM expToValue es
                              Just $ TupVal es'
expToValue (ArrayLit es t _) = do es' <- mapM expToValue es
                                  Just $ arrayVal es' t
expToValue _ = Nothing

-- | The result of applying the arguments of the given types to the
-- given lambda function.
lambdaType :: (Eq vn, Hashable vn) =>
              LambdaBase CompTypeBase vn -> [CompTypeBase vn] -> CompTypeBase vn
lambdaType lam = returnType (lambdaReturnType lam) (lambdaParamDiets lam)

-- | The result of applying the arguments of the given types to a
-- function with the given return type, consuming its parameters with
-- the given diets.
returnType :: (Eq vn, Hashable vn) => DeclTypeBase vn -> [Diet] -> [CompTypeBase vn] -> CompTypeBase vn
returnType (Array et sz Nonunique NoInfo) ds args = Array et sz Nonunique als
  where als = mconcat $ map aliases $ zipWith maskAliases args ds
returnType (Array et sz Unique NoInfo) _ _ = Array et sz Unique mempty
returnType (Elem (Tuple ets)) ds args =
  Elem $ Tuple $ map (\et -> returnType et ds args) ets
returnType (Elem t) _ _ = Elem t `setAliases` HS.empty

-- | The specified return type of a lambda.
lambdaReturnType :: LambdaBase CompTypeBase vn -> DeclTypeBase vn
lambdaReturnType (AnonymFun _ _ t _) = t
lambdaReturnType (CurryFun _ _ t _)  = toDecl t

-- | The parameter 'Diet's of a lambda.
lambdaParamDiets :: LambdaBase ty vn -> [Diet]
lambdaParamDiets (AnonymFun params _ _ _) = map (diet . identType) params
lambdaParamDiets (CurryFun _ args _ _) = map (const Observe) args

-- | Find the function of the given name in the Futhark program.
funDecByName :: Name -> ProgBase ty vn -> Maybe (FunDecBase ty vn)
funDecByName fname = find (\(fname',_,_,_,_) -> fname == fname') . progFunctions

-- | Return the set of all variable names bound in a program.
progNames :: (Eq vn, Hashable vn) => ProgBase ty vn -> HS.HashSet vn
progNames = execWriter . mapM funNames . progFunctions
  where names = identityWalker {
                  walkOnExp = expNames
                , walkOnLambda = lambdaNames
                , walkOnPattern = tell . patNameSet
                }

        one = tell . HS.singleton . identName
        funNames (_, _, params, body, _) =
          mapM_ one params >> expNames body

        expNames e@(LetWith _ dest _ _ _ _ _ _) =
          one dest >> walkExpM names e
        expNames e@(DoLoop _ _ i _ _ _ _) =
          one i >> walkExpM names e
        expNames e = walkExpM names e

        lambdaNames (AnonymFun params body _ _) =
          mapM_ one params >> expNames body
        lambdaNames (CurryFun _ exps _ _) =
          mapM_ expNames exps

-- | Change those subexpressions where evaluation of the expression
-- would stop.  Also change type annotations at branches.
mapTails :: (ExpBase ty vn -> ExpBase ty vn) -> (ty vn -> ty vn)
         -> ExpBase ty vn -> ExpBase ty vn
mapTails f g (LetPat pat e body loc) =
  LetPat pat e (mapTails f g body) loc
mapTails f g (LetWith cs dest src csidx idxs ve body loc) =
  LetWith cs dest src csidx idxs ve (mapTails f g body) loc
mapTails f g (DoLoop pat me i bound loopbody body loc) =
  DoLoop pat me i bound loopbody (mapTails f g body) loc
mapTails f g (If c te fe t loc) =
  If c (mapTails f g te) (mapTails f g fe) (g t) loc
mapTails f _ e = f e

-- | Return the set of identifiers that are free in the given
-- expression.
freeInExp :: (Eq vn, Hashable vn) => ExpBase ty vn -> HS.HashSet (IdentBase ty vn)
freeInExp = execWriter . expFree
  where names = identityWalker {
                  walkOnExp = expFree
                , walkOnLambda = lambdaFree
                , walkOnIdent = identFree
                , walkOnCertificates = mapM_ identFree
                }

        identFree ident =
          tell $ HS.singleton ident

        expFree (LetPat pat e body _) = do
          expFree e
          binding (patIdentSet pat) $ expFree body
        expFree (LetWith cs dest src idxcs idxs ve body _) = do
          mapM_ identFree cs
          identFree src
          mapM_ identFree $ fromMaybe [] idxcs
          mapM_ expFree idxs
          expFree ve
          binding (HS.singleton dest) $ expFree body
        expFree (DoLoop pat mergeexp i boundexp loopbody letbody _) = do
          expFree mergeexp
          expFree boundexp
          binding (i `HS.insert` patIdentSet pat) $ do
            expFree loopbody
            expFree letbody
        expFree e = walkExpM names e

        lambdaFree = tell . freeInLambda

        binding bound = censor (`HS.difference` bound)

-- | As 'freeInExp', but returns the raw names rather than 'IdentBase's.
freeNamesInExp :: (Eq vn, Hashable vn) => ExpBase ty vn -> HS.HashSet vn
freeNamesInExp = HS.map identName . freeInExp

-- | Return the set of identifiers that are free in the given lambda.
freeInLambda :: (Eq vn, Hashable vn) => LambdaBase ty vn -> HS.HashSet (IdentBase ty vn)
freeInLambda (AnonymFun params body _ _) =
  HS.filter ((`notElem` params') . identName) $ freeInExp body
    where params' = map identName params
freeInLambda (CurryFun _ exps _ _) =
  HS.unions (map freeInExp exps)

-- | Convert an identifier to a 'ParamBase'.
toParam :: IdentBase (TypeBase as) vn -> ParamBase vn
toParam (Ident name t loc) = Ident name (toDecl t) loc

-- | Convert a 'ParamBase' to an identifier.
fromParam :: ParamBase vn -> IdentBase CompTypeBase vn
fromParam (Ident name t loc) = Ident name (fromDecl t) loc

-- | The list of names bound in the given pattern.
patNames :: (Eq vn, Hashable vn) => TupIdentBase ty vn -> [vn]
patNames = map identName . patIdents

-- | As 'patNames', but returns a the set of names (which means that
-- information about ordering is destroyed - make sure this is what
-- you want).
patNameSet :: (Eq vn, Hashable vn) => TupIdentBase ty vn -> HS.HashSet vn
patNameSet = HS.map identName . patIdentSet

-- | The list of idents bound in the given pattern.  The order of
-- idents is given by the pre-order traversal of the pattern.
patIdents :: (Eq vn, Hashable vn) => TupIdentBase ty vn -> [IdentBase ty vn]
patIdents (Id ident)     = [ident]
patIdents (TupId pats _) = mconcat $ map patIdents pats
patIdents (Wildcard _ _) = []

-- | As 'patIdents', but returns a the set of names (which means that
-- information about ordering is destroyed - make sure this is what
-- you want).
patIdentSet :: (Eq vn, Hashable vn) => TupIdentBase ty vn -> HS.HashSet (IdentBase ty vn)
patIdentSet = HS.fromList . patIdents

-- | A type with no aliasing information.
type UncheckedType = TypeBase NoInfo Name

-- | An identifier with no type annotations.
type UncheckedIdent = IdentBase NoInfo Name

-- | An expression with no type annotations.
type UncheckedExp = ExpBase NoInfo Name

-- | A lambda with no type annotations.
type UncheckedLambda = LambdaBase NoInfo Name

-- | A pattern with no type annotations.
type UncheckedTupIdent = TupIdentBase NoInfo Name

-- | A function declaration with no type annotations.
type UncheckedFunDec = FunDecBase NoInfo Name

-- | An Futhark program with no type annotations.
type UncheckedProg = ProgBase NoInfo Name