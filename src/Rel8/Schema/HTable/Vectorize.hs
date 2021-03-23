{-# language AllowAmbiguousTypes #-}
{-# language ConstraintKinds #-}
{-# language DataKinds #-}
{-# language FlexibleContexts #-}
{-# language FlexibleInstances #-}
{-# language GADTs #-}
{-# language InstanceSigs #-}
{-# language MultiParamTypeClasses #-}
{-# language NamedFieldPuns #-}
{-# language QuantifiedConstraints #-}
{-# language RankNTypes #-}
{-# language RecordWildCards #-}
{-# language ScopedTypeVariables #-}
{-# language StandaloneKindSignatures #-}
{-# language TypeApplications #-}
{-# language TypeFamilies #-}
{-# language TypeOperators #-}
{-# language UndecidableInstances #-}

module Rel8.Schema.HTable.Vectorize
  ( HVectorize( HVectorize )
  , hvectorize, hunvectorize
  , happend, hempty
  , hrelabel
  )
where

-- base
import Data.Kind ( Constraint, Type )
import Data.List.NonEmpty ( NonEmpty )
import Data.Type.Equality ( (:~:)( Refl ) )
import Prelude

-- rel8
import Rel8.Schema.Context.Label ( Labelable, labeler, unlabeler )
import Rel8.Schema.Dict ( Dict( Dict ) )
import Rel8.Schema.HTable
  ( HTable, HConstrainTable, HField
  , hfield, htabulate, htabulateA, htraverse, hdicts, hspecs
  )
import Rel8.Schema.HTable.Context ( HKTable )
import Rel8.Schema.Nullability ( IsMaybe, Nullability( NonNullable ) )
import Rel8.Schema.Spec ( Context, Spec( Spec ), SSpec(..), Interpretation( Col ) )
import Rel8.Type.Array ( listTypeInformation, nonEmptyTypeInformation )
import Rel8.Type.Information ( TypeInformation )

-- semialign
import Data.Zip ( Unzip, Repeat, Zippy(..) )
import Rel8.Schema.Context (Col)


class Vector list where
  listIsn'tMaybe :: proxy a -> IsMaybe (list a) :~: 'False
  vectorTypeInformation :: ()
    => Nullability a ma
    -> TypeInformation a
    -> TypeInformation (list ma)


instance Vector [] where
  listIsn'tMaybe _ = Refl
  vectorTypeInformation = listTypeInformation


instance Vector NonEmpty where
  listIsn'tMaybe _ = Refl
  vectorTypeInformation = nonEmptyTypeInformation


type HVectorize :: (Type -> Type) -> HKTable -> HKTable
data HVectorize list table context where
  HVectorize :: table (Col VectorizeF) -> HVectorize list table context


type HVectorizeField :: (Type -> Type) -> HKTable -> Context
data HVectorizeField list table spec where
  HVectorizeField
    :: HField table ('Spec labels necessity db a)
    -> HVectorizeField list table
       ('Spec labels necessity (list a) (list a)
       )


instance (HTable table, Vector list) => HTable (HVectorize list table) where

  type HField (HVectorize list table) = HVectorizeField list table
  type HConstrainTable (HVectorize list table) c =
    HConstrainTable table (VectorizeSpecC list c)

  hfield (HVectorize table) (HVectorizeField field) =
    getVectorizeSpec (hfield table field)

  htabulate f = HVectorize $ htabulate $ \field -> case hfield hspecs field of
    SSpec {} -> VectorizeSpec (f (HVectorizeField field))
  htraverse f (HVectorize t) = HVectorize <$> htraverse (traverseVectorizeSpec f) t

  hdicts :: forall c. HConstrainTable table (VectorizeSpecC list c) =>
    HVectorize list table (Dict c)
  hdicts = HVectorize $ htabulate $ \field -> case hfield hspecs field of
    SSpec {} -> case hfield (hdicts @_ @(VectorizeSpecC list c)) field of
      Dict -> VectorizeSpec Dict

  hspecs = HVectorize $ htabulate $ \field -> case hfield hspecs field of
    SSpec {..} -> case listIsn'tMaybe @list nullability of
      Refl -> VectorizeSpec SSpec
        { nullability = NonNullable
        , info = vectorTypeInformation nullability info
        , ..
        }

  {-# INLINABLE hfield #-}
  {-# INLINABLE htabulate #-}
  {-# INLINABLE htraverse #-}
  {-# INLINABLE hdicts #-}
  {-# INLINABLE hspecs #-}


type VectorizingSpec :: Type -> Type
type VectorizingSpec r = (Type -> Type) -> (Spec -> r) -> Spec -> r


type VectorizeF :: Type -> Type
data VectorizeF a


instance Interpretation VectorizeF where
  data Col VectorizeF :: Spec -> Type where
    VectorizeSpec ::
      { getVectorizeSpec :: context ('Spec labels necessity (list a) (list a))
      } -> Col VectorizeF ('Spec labels necessity db a)


instance Labelable context => Labelable VectorizeF where
  labeler (VectorizeSpec a) = VectorizeSpec (labeler a)
  unlabeler (VectorizeSpec a) = VectorizeSpec (unlabeler a)


type VectorizeSpecC :: VectorizingSpec Constraint
class
  ( forall labels necessity db a.
    ( spec ~ 'Spec labels necessity db a
      => constraint ('Spec labels necessity (list a) (list a))
    )
  )
  => VectorizeSpecC list constraint spec
instance
  ( spec ~ 'Spec labels necessity db a
  , constraint ('Spec labels necessity (list a) (list a))
  )
  => VectorizeSpecC list constraint spec


traverseVectorizeSpec :: forall context context' list spec m. Functor m
  => (forall x. context x -> m (context' x))
  -> Col  VectorizeSpec list context spec
  -> m (VectorizeSpec list context' spec)
traverseVectorizeSpec f (VectorizeSpec a) = VectorizeSpec <$> f a


hvectorize :: (HTable t, Unzip f)
  => (forall labels necessity db a. ()
    => SSpec ('Spec labels necessity db a)
    -> f (context ('Spec labels necessity db a))
    -> context' ('Spec labels necessity (list a) (list a)))
  -> f (t context)
  -> HVectorize list t context'
hvectorize vectorizer as = HVectorize $ htabulate $ \field ->
  case hfield hspecs field of
    spec@SSpec {} -> VectorizeSpec (vectorizer spec (fmap (`hfield` field) as))
{-# INLINABLE hvectorize #-}


hunvectorize :: (HTable t, Repeat f)
  => (forall labels necessity db a. ()
    => SSpec ('Spec labels necessity db a)
    -> context ('Spec labels necessity (list a) (list a))
    -> f (context' ('Spec labels necessity db a)))
  -> HVectorize list t context
  -> f (t context')
hunvectorize unvectorizer (HVectorize table) =
  getZippy $ htabulateA $ \field -> case hfield hspecs field of
    spec -> case hfield table field of
      VectorizeSpec a -> Zippy (unvectorizer spec a)
{-# INLINABLE hunvectorize #-}


happend :: HTable t =>
  ( forall labels necessity db a. ()
    => Nullability db a
    -> TypeInformation db
    -> context ('Spec labels necessity (list a) (list a))
    -> context ('Spec labels necessity (list a) (list a))
    -> context ('Spec labels necessity (list a) (list a))
  )
  -> HVectorize list t context
  -> HVectorize list t context
  -> HVectorize list t context
happend append (HVectorize as) (HVectorize bs) = HVectorize $
  htabulate $ \field -> case (hfield as field, hfield bs field) of
    (VectorizeSpec a, VectorizeSpec b) -> case hfield hspecs field of
      SSpec {nullability, info} -> VectorizeSpec $ append nullability info a b


hempty :: HTable t =>
  ( forall labels necessity db a. ()
    => Nullability db a
    -> TypeInformation db
    -> context ('Spec labels necessity [a] [a])
  )
  -> HVectorize [] t context
hempty empty = HVectorize $ htabulate $ \field -> case hfield hspecs field of
  SSpec {nullability, info} -> VectorizeSpec (empty nullability info)


hrelabel :: Labelable context
  => (forall ctx. Labelable ctx => t ctx -> u ctx)
  -> HVectorize list t context
  -> HVectorize list u context
hrelabel f (HVectorize table) = HVectorize (f table)
