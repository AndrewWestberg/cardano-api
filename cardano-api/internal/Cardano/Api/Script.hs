{-# LANGUAGE DataKinds #-}
{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DerivingVia #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE InstanceSigs #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE NamedFieldPuns #-}
{-# LANGUAGE PatternSynonyms #-}
{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE StandaloneDeriving #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE TypeOperators #-}

{- HLINT ignore "Avoid lambda using `infix`" -}
{- HLINT ignore "Use section" -}

module Cardano.Api.Script
  ( -- * Languages
    SimpleScript'
  , PlutusScriptV1
  , PlutusScriptV2
  , PlutusScriptV3
  , ScriptLanguage (..)
  , PlutusScriptVersion (..)
  , AnyScriptLanguage (..)
  , AnyPlutusScriptVersion (..)
  , IsPlutusScriptLanguage (..)
  , IsScriptLanguage (..)

    -- * Scripts in a specific language
  , Script (..)

    -- * Scripts in any language
  , ScriptInAnyLang (..)
  , toScriptInAnyLang

    -- * Scripts in an era
  , ScriptInEra (..)
  , toScriptInEra
  , eraOfScriptInEra
  , HasScriptLanguageInEra (..)
  , ToAlonzoScript (..)

    -- * Reference scripts
  , ReferenceScript (..)
  , refScriptToShelleyScript

    -- * Use of a script in an era as a witness
  , WitCtxTxIn
  , WitCtxMint
  , WitCtxStake
  , WitCtx (..)
  , ScriptWitness (..)
  , Witness (..)
  , KeyWitnessInCtx (..)
  , ScriptWitnessInCtx (..)
  , IsScriptWitnessInCtx (..)
  , ScriptDatum (..)
  , ScriptRedeemer
  , scriptWitnessScript

    -- ** Languages supported in each era
  , ScriptLanguageInEra (..)
  , scriptLanguageSupportedInEra
  , languageOfScriptLanguageInEra
  , eraOfScriptLanguageInEra

    -- * The simple script language
  , SimpleScript (..)
  , SimpleScriptOrReferenceInput (..)

    -- * The Plutus script language
  , PlutusScript (..)
  , PlutusScriptOrReferenceInput (..)
  , examplePlutusScriptAlwaysSucceeds
  , examplePlutusScriptAlwaysFails

    -- * Script data
  , ScriptData (..)

    -- * Script execution units
  , ExecutionUnits (..)

    -- * Script hashes
  , ScriptHash (..)
  , hashScript

    -- * Internal conversion functions
  , toShelleyScript
  , fromShelleyBasedScript
  , toShelleyMultiSig
  , fromShelleyMultiSig
  , toAllegraTimelock
  , fromAllegraTimelock
  , toAlonzoExUnits
  , fromAlonzoExUnits
  , toShelleyScriptHash
  , fromShelleyScriptHash
  , toPlutusData
  , fromPlutusData
  , toAlonzoData
  , fromAlonzoData
  , toAlonzoLanguage
  , fromAlonzoLanguage
  , fromShelleyScriptToReferenceScript
  , scriptInEraToRefScript

    -- * Data family instances
  , AsType (..)
  , Hash (..)
  )
where

import           Cardano.Api.Eon.BabbageEraOnwards
import           Cardano.Api.Eon.ShelleyBasedEra
import           Cardano.Api.Eras.Case
import           Cardano.Api.Eras.Core
import           Cardano.Api.Error
import           Cardano.Api.Hash
import           Cardano.Api.HasTypeProxy
import           Cardano.Api.Keys.Shelley
import           Cardano.Api.ScriptData
import           Cardano.Api.SerialiseCBOR
import           Cardano.Api.SerialiseJSON
import           Cardano.Api.SerialiseRaw
import           Cardano.Api.SerialiseTextEnvelope
import           Cardano.Api.SerialiseUsing
import           Cardano.Api.TxIn
import           Cardano.Api.Utils (failEitherWith)

import qualified Cardano.Binary as CBOR
import qualified Cardano.Crypto.Hash.Class as Crypto
import qualified Cardano.Ledger.Allegra.Scripts as Allegra
import qualified Cardano.Ledger.Allegra.Scripts as Timelock
import qualified Cardano.Ledger.Alonzo.Scripts as Alonzo
import qualified Cardano.Ledger.Babbage.Scripts as Babbage
import           Cardano.Ledger.BaseTypes (StrictMaybe (..))
import qualified Cardano.Ledger.Binary as Binary (decCBOR, decodeFullAnnotator)
import qualified Cardano.Ledger.Conway.Scripts as Conway
import           Cardano.Ledger.Core (Era (EraCrypto))
import qualified Cardano.Ledger.Core as Ledger
import qualified Cardano.Ledger.Keys as Shelley
import qualified Cardano.Ledger.Plutus.Language as Plutus
import qualified Cardano.Ledger.Shelley.Scripts as Shelley
import           Cardano.Slotting.Slot (SlotNo)
import           Ouroboros.Consensus.Shelley.Eras (StandardCrypto)
import qualified PlutusLedgerApi.Test.Examples as Plutus

import           Control.Applicative
import           Control.Monad
import           Data.Aeson (Value (..), object, (.:), (.=))
import qualified Data.Aeson as Aeson
import qualified Data.Aeson.Types as Aeson
import qualified Data.ByteString.Lazy as LBS
import           Data.ByteString.Short (ShortByteString)
import qualified Data.ByteString.Short as SBS
import           Data.Either.Combinators (maybeToRight)
import           Data.Foldable (toList)
import           Data.Functor
import           Data.Scientific (toBoundedInteger)
import qualified Data.Sequence.Strict as Seq
import           Data.String (IsString)
import           Data.Text (Text)
import qualified Data.Text as Text
import qualified Data.Text.Encoding as Text
import           Data.Type.Equality (TestEquality (..), (:~:) (Refl))
import           Data.Typeable (Typeable)
import           Data.Vector (Vector)
import           Numeric.Natural (Natural)

-- ----------------------------------------------------------------------------
-- Types for script language and version
--

data SimpleScript'

-- | The original simple script language which supports
--
-- * require a signature from a given key (by verification key hash)
-- * n-way and combinator
-- * n-way or combinator
-- * m-of-n combinator
--
-- This version of the language was introduced in the 'ShelleyEra'.

-- | The second version of the simple script language. It has all the features
-- of the original simple script language plus new atomic predicates:
--
-- * require the time be before a given slot number
-- * require the time be after a given slot number
--
-- This version of the language was introduced in the 'AllegraEra'.
--
-- However we opt for a single type level tag 'SimpleScript'' as the second version of
-- of the language introduced in the Allegra era is a superset of the language introduced
-- in the Shelley era.

-- | Place holder type to show what the pattern is to extend to multiple
-- languages, not just multiple versions of a single language.
data PlutusScriptV1

data PlutusScriptV2

data PlutusScriptV3

instance HasTypeProxy SimpleScript' where
  data AsType SimpleScript' = AsSimpleScript
  proxyToAsType _ = AsSimpleScript

instance HasTypeProxy PlutusScriptV1 where
  data AsType PlutusScriptV1 = AsPlutusScriptV1
  proxyToAsType :: Proxy PlutusScriptV1 -> AsType PlutusScriptV1
  proxyToAsType _ = AsPlutusScriptV1

instance HasTypeProxy PlutusScriptV2 where
  data AsType PlutusScriptV2 = AsPlutusScriptV2
  proxyToAsType _ = AsPlutusScriptV2

instance HasTypeProxy PlutusScriptV3 where
  data AsType PlutusScriptV3 = AsPlutusScriptV3
  proxyToAsType _ = AsPlutusScriptV3

-- ----------------------------------------------------------------------------
-- Value level representation for script languages
--
data ScriptLanguage lang where
  SimpleScriptLanguage :: ScriptLanguage SimpleScript'
  PlutusScriptLanguage :: PlutusScriptVersion lang -> ScriptLanguage lang

deriving instance (Eq (ScriptLanguage lang))

deriving instance (Show (ScriptLanguage lang))

instance TestEquality ScriptLanguage where
  testEquality SimpleScriptLanguage SimpleScriptLanguage = Just Refl
  testEquality
    (PlutusScriptLanguage lang)
    (PlutusScriptLanguage lang') = testEquality lang lang'
  testEquality _ _ = Nothing

data PlutusScriptVersion lang where
  PlutusScriptV1 :: PlutusScriptVersion PlutusScriptV1
  PlutusScriptV2 :: PlutusScriptVersion PlutusScriptV2
  PlutusScriptV3 :: PlutusScriptVersion PlutusScriptV3

deriving instance (Eq (PlutusScriptVersion lang))

deriving instance (Show (PlutusScriptVersion lang))

instance TestEquality PlutusScriptVersion where
  testEquality PlutusScriptV1 PlutusScriptV1 = Just Refl
  testEquality PlutusScriptV2 PlutusScriptV2 = Just Refl
  testEquality PlutusScriptV3 PlutusScriptV3 = Just Refl
  testEquality _ _ = Nothing

data AnyScriptLanguage where
  AnyScriptLanguage :: ScriptLanguage lang -> AnyScriptLanguage

deriving instance (Show AnyScriptLanguage)

instance Eq AnyScriptLanguage where
  a == b = fromEnum a == fromEnum b

instance Ord AnyScriptLanguage where
  compare a b = compare (fromEnum a) (fromEnum b)

instance Enum AnyScriptLanguage where
  toEnum 0 = AnyScriptLanguage SimpleScriptLanguage
  toEnum 1 = AnyScriptLanguage (PlutusScriptLanguage PlutusScriptV1)
  toEnum 2 = AnyScriptLanguage (PlutusScriptLanguage PlutusScriptV2)
  toEnum 3 = AnyScriptLanguage (PlutusScriptLanguage PlutusScriptV3)
  toEnum err = error $ "AnyScriptLanguage.toEnum: bad argument: " <> show err

  fromEnum (AnyScriptLanguage SimpleScriptLanguage) = 0
  fromEnum (AnyScriptLanguage (PlutusScriptLanguage PlutusScriptV1)) = 1
  fromEnum (AnyScriptLanguage (PlutusScriptLanguage PlutusScriptV2)) = 2
  fromEnum (AnyScriptLanguage (PlutusScriptLanguage PlutusScriptV3)) = 3

instance Bounded AnyScriptLanguage where
  minBound = AnyScriptLanguage SimpleScriptLanguage
  maxBound = AnyScriptLanguage (PlutusScriptLanguage PlutusScriptV3)

data AnyPlutusScriptVersion where
  AnyPlutusScriptVersion
    :: PlutusScriptVersion lang
    -> AnyPlutusScriptVersion

deriving instance (Show AnyPlutusScriptVersion)

instance Eq AnyPlutusScriptVersion where
  a == b = fromEnum a == fromEnum b

instance Ord AnyPlutusScriptVersion where
  compare a b = compare (fromEnum a) (fromEnum b)

instance Enum AnyPlutusScriptVersion where
  toEnum 0 = AnyPlutusScriptVersion PlutusScriptV1
  toEnum 1 = AnyPlutusScriptVersion PlutusScriptV2
  toEnum 2 = AnyPlutusScriptVersion PlutusScriptV3
  toEnum err = error $ "AnyPlutusScriptVersion.toEnum: bad argument: " <> show err

  fromEnum (AnyPlutusScriptVersion PlutusScriptV1) = 0
  fromEnum (AnyPlutusScriptVersion PlutusScriptV2) = 1
  fromEnum (AnyPlutusScriptVersion PlutusScriptV3) = 2

instance Bounded AnyPlutusScriptVersion where
  minBound = AnyPlutusScriptVersion PlutusScriptV1
  maxBound = AnyPlutusScriptVersion PlutusScriptV3

instance ToCBOR AnyPlutusScriptVersion where
  toCBOR = toCBOR . fromEnum

instance FromCBOR AnyPlutusScriptVersion where
  fromCBOR = do
    n <- fromCBOR
    if n >= fromEnum (minBound :: AnyPlutusScriptVersion)
      && n <= fromEnum (maxBound :: AnyPlutusScriptVersion)
      then return $! toEnum n
      else fail "plutus script version out of bounds"

instance ToJSON AnyPlutusScriptVersion where
  toJSON (AnyPlutusScriptVersion PlutusScriptV1) =
    Aeson.String "PlutusScriptV1"
  toJSON (AnyPlutusScriptVersion PlutusScriptV2) =
    Aeson.String "PlutusScriptV2"
  toJSON (AnyPlutusScriptVersion PlutusScriptV3) =
    Aeson.String "PlutusScriptV3"

parsePlutusScriptVersion :: Text -> Aeson.Parser AnyPlutusScriptVersion
parsePlutusScriptVersion t =
  case t of
    "PlutusScriptV1" -> return (AnyPlutusScriptVersion PlutusScriptV1)
    "PlutusScriptV2" -> return (AnyPlutusScriptVersion PlutusScriptV2)
    "PlutusScriptV3" -> return (AnyPlutusScriptVersion PlutusScriptV3)
    _ -> fail "Expected PlutusScriptVX, for X = 1, 2, or 3"

instance FromJSON AnyPlutusScriptVersion where
  parseJSON = Aeson.withText "PlutusScriptVersion" parsePlutusScriptVersion

instance Aeson.FromJSONKey AnyPlutusScriptVersion where
  fromJSONKey = Aeson.FromJSONKeyTextParser parsePlutusScriptVersion

instance Aeson.ToJSONKey AnyPlutusScriptVersion where
  toJSONKey = Aeson.toJSONKeyText toText
   where
    toText :: AnyPlutusScriptVersion -> Text
    toText (AnyPlutusScriptVersion PlutusScriptV1) = "PlutusScriptV1"
    toText (AnyPlutusScriptVersion PlutusScriptV2) = "PlutusScriptV2"
    toText (AnyPlutusScriptVersion PlutusScriptV3) = "PlutusScriptV3"

toAlonzoLanguage :: AnyPlutusScriptVersion -> Plutus.Language
toAlonzoLanguage (AnyPlutusScriptVersion PlutusScriptV1) = Plutus.PlutusV1
toAlonzoLanguage (AnyPlutusScriptVersion PlutusScriptV2) = Plutus.PlutusV2
toAlonzoLanguage (AnyPlutusScriptVersion PlutusScriptV3) = Plutus.PlutusV3

fromAlonzoLanguage :: Plutus.Language -> AnyPlutusScriptVersion
fromAlonzoLanguage Plutus.PlutusV1 = AnyPlutusScriptVersion PlutusScriptV1
fromAlonzoLanguage Plutus.PlutusV2 = AnyPlutusScriptVersion PlutusScriptV2
fromAlonzoLanguage Plutus.PlutusV3 = AnyPlutusScriptVersion PlutusScriptV3

class HasTypeProxy lang => IsScriptLanguage lang where
  scriptLanguage :: ScriptLanguage lang

instance IsScriptLanguage SimpleScript' where
  scriptLanguage = SimpleScriptLanguage

instance IsScriptLanguage PlutusScriptV1 where
  scriptLanguage = PlutusScriptLanguage PlutusScriptV1

instance IsScriptLanguage PlutusScriptV2 where
  scriptLanguage = PlutusScriptLanguage PlutusScriptV2

instance IsScriptLanguage PlutusScriptV3 where
  scriptLanguage = PlutusScriptLanguage PlutusScriptV3

class IsScriptLanguage lang => IsPlutusScriptLanguage lang where
  plutusScriptVersion :: PlutusScriptVersion lang

instance IsPlutusScriptLanguage PlutusScriptV1 where
  plutusScriptVersion = PlutusScriptV1

instance IsPlutusScriptLanguage PlutusScriptV2 where
  plutusScriptVersion = PlutusScriptV2

instance IsPlutusScriptLanguage PlutusScriptV3 where
  plutusScriptVersion = PlutusScriptV3

-- ----------------------------------------------------------------------------
-- Script type: covering all script languages
--

-- | A script in a particular language.
--
-- See also 'ScriptInAnyLang' for a script in any of the known languages.
--
-- See also 'ScriptInEra' for a script in a language that is available within
-- a particular era.
--
-- Note that some but not all scripts have an external JSON syntax, hence this
-- type has no JSON serialisation instances. The 'SimpleScript' family of
-- languages do have a JSON syntax and thus have 'ToJSON'\/'FromJSON' instances.
data Script lang where
  SimpleScript
    :: !SimpleScript
    -> Script SimpleScript'
  PlutusScript
    :: !(PlutusScriptVersion lang)
    -> !(PlutusScript lang)
    -> Script lang

deriving instance (Eq (Script lang))

deriving instance (Show (Script lang))

instance HasTypeProxy lang => HasTypeProxy (Script lang) where
  data AsType (Script lang) = AsScript (AsType lang)
  proxyToAsType _ = AsScript (proxyToAsType (Proxy :: Proxy lang))

instance IsScriptLanguage lang => SerialiseAsCBOR (Script lang) where
  serialiseToCBOR (SimpleScript s) =
    CBOR.serialize' (toAllegraTimelock s :: Timelock.Timelock (ShelleyLedgerEra AllegraEra))
  serialiseToCBOR (PlutusScript PlutusScriptV1 s) =
    CBOR.serialize' s
  serialiseToCBOR (PlutusScript PlutusScriptV2 s) =
    CBOR.serialize' s
  serialiseToCBOR (PlutusScript PlutusScriptV3 s) =
    CBOR.serialize' s

  deserialiseFromCBOR _ bs =
    case scriptLanguage :: ScriptLanguage lang of
      SimpleScriptLanguage ->
        let version = Ledger.eraProtVerLow @(ShelleyLedgerEra AllegraEra)
         in SimpleScript . fromAllegraTimelock @(ShelleyLedgerEra AllegraEra)
              <$> Binary.decodeFullAnnotator version "Script" Binary.decCBOR (LBS.fromStrict bs)
      PlutusScriptLanguage PlutusScriptV1 ->
        PlutusScript PlutusScriptV1
          <$> CBOR.decodeFull' bs
      PlutusScriptLanguage PlutusScriptV2 ->
        PlutusScript PlutusScriptV2
          <$> CBOR.decodeFull' bs
      PlutusScriptLanguage PlutusScriptV3 ->
        PlutusScript PlutusScriptV3
          <$> CBOR.decodeFull' bs

instance IsScriptLanguage lang => HasTextEnvelope (Script lang) where
  textEnvelopeType _ =
    case scriptLanguage :: ScriptLanguage lang of
      SimpleScriptLanguage -> "SimpleScript"
      PlutusScriptLanguage PlutusScriptV1 -> "PlutusScriptV1"
      PlutusScriptLanguage PlutusScriptV2 -> "PlutusScriptV2"
      PlutusScriptLanguage PlutusScriptV3 -> "PlutusScriptV3"

-- ----------------------------------------------------------------------------
-- Scripts in any language
--

-- | Sometimes it is necessary to handle all languages without making static
-- type distinctions between languages. For example, when reading external
-- input, or before the era context is known.
--
-- Use 'toScriptInEra' to convert to a script in the context of an era.
data ScriptInAnyLang where
  ScriptInAnyLang
    :: ScriptLanguage lang
    -> Script lang
    -> ScriptInAnyLang

deriving instance Show ScriptInAnyLang

-- The GADT in the ScriptInAnyLang constructor requires a custom Eq instance
instance Eq ScriptInAnyLang where
  (==)
    (ScriptInAnyLang lang script)
    (ScriptInAnyLang lang' script') =
      case testEquality lang lang' of
        Nothing -> False
        Just Refl -> script == script'

instance ToJSON ScriptInAnyLang where
  toJSON (ScriptInAnyLang l s) =
    object
      [ "scriptLanguage" .= show l
      , "script"
          .= obtainScriptLangConstraint
            l
            (serialiseToTextEnvelope Nothing s)
      ]
   where
    obtainScriptLangConstraint
      :: ScriptLanguage lang
      -> (IsScriptLanguage lang => a)
      -> a
    obtainScriptLangConstraint SimpleScriptLanguage f = f
    obtainScriptLangConstraint (PlutusScriptLanguage PlutusScriptV1) f = f
    obtainScriptLangConstraint (PlutusScriptLanguage PlutusScriptV2) f = f
    obtainScriptLangConstraint (PlutusScriptLanguage PlutusScriptV3) f = f

instance FromJSON ScriptInAnyLang where
  parseJSON = Aeson.withObject "ScriptInAnyLang" $ \o -> do
    textEnvelopeScript <- o .: "script"
    case textEnvelopeToScript textEnvelopeScript of
      Left textEnvErr -> fail $ displayError textEnvErr
      Right (ScriptInAnyLang l s) -> pure $ ScriptInAnyLang l s

-- | Convert a script in a specific statically-known language to a
-- 'ScriptInAnyLang'.
--
-- No inverse to this is provided, just do case analysis on the 'ScriptLanguage'
-- field within the 'ScriptInAnyLang' constructor.
toScriptInAnyLang :: Script lang -> ScriptInAnyLang
toScriptInAnyLang s@(SimpleScript _) =
  ScriptInAnyLang SimpleScriptLanguage s
toScriptInAnyLang s@(PlutusScript v _) =
  ScriptInAnyLang (PlutusScriptLanguage v) s

instance HasTypeProxy ScriptInAnyLang where
  data AsType ScriptInAnyLang = AsScriptInAnyLang
  proxyToAsType _ = AsScriptInAnyLang

-- ----------------------------------------------------------------------------
-- Scripts in the context of a ledger era
--

data ScriptInEra era where
  ScriptInEra
    :: ScriptLanguageInEra lang era
    -> Script lang
    -> ScriptInEra era

deriving instance Show (ScriptInEra era)

-- The GADT in the ScriptInEra constructor requires a custom instance
instance Eq (ScriptInEra era) where
  (==)
    (ScriptInEra langInEra script)
    (ScriptInEra langInEra' script') =
      case testEquality
        (languageOfScriptLanguageInEra langInEra)
        (languageOfScriptLanguageInEra langInEra') of
        Nothing -> False
        Just Refl -> script == script'

data ScriptLanguageInEra lang era where
  SimpleScriptInShelley :: ScriptLanguageInEra SimpleScript' ShelleyEra
  SimpleScriptInAllegra :: ScriptLanguageInEra SimpleScript' AllegraEra
  SimpleScriptInMary :: ScriptLanguageInEra SimpleScript' MaryEra
  SimpleScriptInAlonzo :: ScriptLanguageInEra SimpleScript' AlonzoEra
  SimpleScriptInBabbage :: ScriptLanguageInEra SimpleScript' BabbageEra
  SimpleScriptInConway :: ScriptLanguageInEra SimpleScript' ConwayEra
  PlutusScriptV1InAlonzo :: ScriptLanguageInEra PlutusScriptV1 AlonzoEra
  PlutusScriptV1InBabbage :: ScriptLanguageInEra PlutusScriptV1 BabbageEra
  PlutusScriptV1InConway :: ScriptLanguageInEra PlutusScriptV1 ConwayEra
  PlutusScriptV2InBabbage :: ScriptLanguageInEra PlutusScriptV2 BabbageEra
  PlutusScriptV2InConway :: ScriptLanguageInEra PlutusScriptV2 ConwayEra
  PlutusScriptV3InConway :: ScriptLanguageInEra PlutusScriptV3 ConwayEra

deriving instance Eq (ScriptLanguageInEra lang era)

deriving instance Show (ScriptLanguageInEra lang era)

instance ToJSON (ScriptLanguageInEra lang era) where
  toJSON sLangInEra = Aeson.String . Text.pack $ show sLangInEra

instance HasTypeProxy era => HasTypeProxy (ScriptInEra era) where
  data AsType (ScriptInEra era) = AsScriptInEra (AsType era)
  proxyToAsType _ = AsScriptInEra (proxyToAsType (Proxy :: Proxy era))

-- | Check if a given script language is supported in a given era, and if so
-- return the evidence.
scriptLanguageSupportedInEra
  :: ShelleyBasedEra era
  -> ScriptLanguage lang
  -> Maybe (ScriptLanguageInEra lang era)
scriptLanguageSupportedInEra era lang =
  case (era, lang) of
    (ShelleyBasedEraShelley, SimpleScriptLanguage) ->
      Just SimpleScriptInShelley
    (ShelleyBasedEraAllegra, SimpleScriptLanguage) ->
      Just SimpleScriptInAllegra
    (ShelleyBasedEraMary, SimpleScriptLanguage) ->
      Just SimpleScriptInMary
    (ShelleyBasedEraAlonzo, SimpleScriptLanguage) ->
      Just SimpleScriptInAlonzo
    (ShelleyBasedEraBabbage, SimpleScriptLanguage) ->
      Just SimpleScriptInBabbage
    (ShelleyBasedEraConway, SimpleScriptLanguage) ->
      Just SimpleScriptInConway
    (ShelleyBasedEraAlonzo, PlutusScriptLanguage PlutusScriptV1) ->
      Just PlutusScriptV1InAlonzo
    (ShelleyBasedEraBabbage, PlutusScriptLanguage PlutusScriptV1) ->
      Just PlutusScriptV1InBabbage
    (ShelleyBasedEraBabbage, PlutusScriptLanguage PlutusScriptV2) ->
      Just PlutusScriptV2InBabbage
    (ShelleyBasedEraConway, PlutusScriptLanguage PlutusScriptV1) ->
      Just PlutusScriptV1InConway
    (ShelleyBasedEraConway, PlutusScriptLanguage PlutusScriptV2) ->
      Just PlutusScriptV2InConway
    (ShelleyBasedEraConway, PlutusScriptLanguage PlutusScriptV3) ->
      Just PlutusScriptV3InConway
    _ -> Nothing

languageOfScriptLanguageInEra
  :: ScriptLanguageInEra lang era
  -> ScriptLanguage lang
languageOfScriptLanguageInEra langInEra =
  case langInEra of
    SimpleScriptInShelley -> SimpleScriptLanguage
    SimpleScriptInAllegra -> SimpleScriptLanguage
    SimpleScriptInMary -> SimpleScriptLanguage
    SimpleScriptInAlonzo -> SimpleScriptLanguage
    SimpleScriptInBabbage -> SimpleScriptLanguage
    SimpleScriptInConway -> SimpleScriptLanguage
    PlutusScriptV1InAlonzo -> PlutusScriptLanguage PlutusScriptV1
    PlutusScriptV1InBabbage -> PlutusScriptLanguage PlutusScriptV1
    PlutusScriptV1InConway -> PlutusScriptLanguage PlutusScriptV1
    PlutusScriptV2InBabbage -> PlutusScriptLanguage PlutusScriptV2
    PlutusScriptV2InConway -> PlutusScriptLanguage PlutusScriptV2
    PlutusScriptV3InConway -> PlutusScriptLanguage PlutusScriptV3

eraOfScriptLanguageInEra
  :: ScriptLanguageInEra lang era
  -> ShelleyBasedEra era
eraOfScriptLanguageInEra langInEra =
  case langInEra of
    SimpleScriptInShelley -> ShelleyBasedEraShelley
    SimpleScriptInAllegra -> ShelleyBasedEraAllegra
    SimpleScriptInMary -> ShelleyBasedEraMary
    SimpleScriptInAlonzo -> ShelleyBasedEraAlonzo
    SimpleScriptInBabbage -> ShelleyBasedEraBabbage
    SimpleScriptInConway -> ShelleyBasedEraConway
    PlutusScriptV1InAlonzo -> ShelleyBasedEraAlonzo
    PlutusScriptV1InBabbage -> ShelleyBasedEraBabbage
    PlutusScriptV1InConway -> ShelleyBasedEraConway
    PlutusScriptV2InBabbage -> ShelleyBasedEraBabbage
    PlutusScriptV2InConway -> ShelleyBasedEraConway
    PlutusScriptV3InConway -> ShelleyBasedEraConway

-- | Given a target era and a script in some language, check if the language is
-- supported in that era, and if so return a 'ScriptInEra'.
toScriptInEra :: ShelleyBasedEra era -> ScriptInAnyLang -> Maybe (ScriptInEra era)
toScriptInEra era (ScriptInAnyLang lang s) = do
  lang' <- scriptLanguageSupportedInEra era lang
  return (ScriptInEra lang' s)

eraOfScriptInEra :: ScriptInEra era -> ShelleyBasedEra era
eraOfScriptInEra (ScriptInEra langInEra _) = eraOfScriptLanguageInEra langInEra

-- ----------------------------------------------------------------------------
-- Scripts used in a transaction (in an era) to witness authorised use
--

-- | A tag type for the context in which a script is used in a transaction.
--
-- This type tags the context as being to witness a transaction input.
data WitCtxTxIn

-- | A tag type for the context in which a script is used in a transaction.
--
-- This type tags the context as being to witness minting.
data WitCtxMint

-- | A tag type for the context in which a script is used in a transaction.
--
-- This type tags the context as being to witness the use of stake addresses in
-- certificates, withdrawals, voting and proposals.
data WitCtxStake

-- | This GADT provides a value-level representation of all the witness
-- contexts. This enables pattern matching on the context to allow them to be
-- treated in a non-uniform way.
data WitCtx witctx where
  WitCtxTxIn :: WitCtx WitCtxTxIn
  WitCtxMint :: WitCtx WitCtxMint
  WitCtxStake :: WitCtx WitCtxStake

-- | Scripts can now exist in the UTxO at a transaction output. We can
-- reference these scripts via specification of a reference transaction input
-- in order to witness spending inputs, withdrawals, certificates
-- or to mint tokens. This datatype encapsulates this concept.
data PlutusScriptOrReferenceInput lang
  = PScript (PlutusScript lang)
  | -- | Needed to construct the redeemer pointer map
    -- in the case of minting reference scripts where we don't
    -- have direct access to the script
    PReferenceScript
      TxIn
      (Maybe ScriptHash)
  deriving (Eq, Show)

data SimpleScriptOrReferenceInput lang
  = SScript SimpleScript
  | SReferenceScript TxIn (Maybe ScriptHash)
  deriving (Eq, Show)

-- | A /use/ of a script within a transaction body to witness that something is
-- being used in an authorised manner. That can be
--
-- * spending a transaction input
-- * minting tokens
-- * using a certificate (stake address certs specifically)
-- * withdrawing from a reward account
--
-- For simple script languages, the use of the script is the same in all
-- contexts. For Plutus scripts, using a script involves supplying a redeemer.
-- In addition, Plutus scripts used for spending inputs must also supply the
-- datum value used when originally creating the TxOut that is now being spent.
data ScriptWitness witctx era where
  SimpleScriptWitness
    :: ScriptLanguageInEra SimpleScript' era
    -> SimpleScriptOrReferenceInput SimpleScript'
    -> ScriptWitness witctx era
  PlutusScriptWitness
    :: ScriptLanguageInEra lang era
    -> PlutusScriptVersion lang
    -> PlutusScriptOrReferenceInput lang
    -> ScriptDatum witctx
    -> ScriptRedeemer
    -> ExecutionUnits
    -> ScriptWitness witctx era

deriving instance Show (ScriptWitness witctx era)

-- The GADT in the SimpleScriptWitness constructor requires a custom instance
instance Eq (ScriptWitness witctx era) where
  (==)
    (SimpleScriptWitness langInEra script)
    (SimpleScriptWitness langInEra' script') =
      case testEquality
        (languageOfScriptLanguageInEra langInEra)
        (languageOfScriptLanguageInEra langInEra') of
        Nothing -> False
        Just Refl -> script == script'
  (==)
    ( PlutusScriptWitness
        langInEra
        version
        script
        datum
        redeemer
        execUnits
      )
    ( PlutusScriptWitness
        langInEra'
        version'
        script'
        datum'
        redeemer'
        execUnits'
      ) =
      case testEquality
        (languageOfScriptLanguageInEra langInEra)
        (languageOfScriptLanguageInEra langInEra') of
        Nothing -> False
        Just Refl ->
          version == version'
            && script == script'
            && datum == datum'
            && redeemer == redeemer'
            && execUnits == execUnits'
  (==) _ _ = False

type ScriptRedeemer = HashableScriptData

data ScriptDatum witctx where
  ScriptDatumForTxIn :: Maybe HashableScriptData -> ScriptDatum WitCtxTxIn
  InlineScriptDatum :: ScriptDatum WitCtxTxIn
  NoScriptDatumForMint :: ScriptDatum WitCtxMint
  NoScriptDatumForStake :: ScriptDatum WitCtxStake

deriving instance Eq (ScriptDatum witctx)

deriving instance Show (ScriptDatum witctx)

-- We cannot always extract a script from a script witness due to reference scripts.
-- Reference scripts exist in the UTxO, so without access to the UTxO we cannot
-- retrieve the script.
scriptWitnessScript :: ScriptWitness witctx era -> Maybe (ScriptInEra era)
scriptWitnessScript (SimpleScriptWitness SimpleScriptInShelley (SScript script)) =
  Just $ ScriptInEra SimpleScriptInShelley (SimpleScript script)
scriptWitnessScript (SimpleScriptWitness SimpleScriptInAllegra (SScript script)) =
  Just $ ScriptInEra SimpleScriptInAllegra (SimpleScript script)
scriptWitnessScript (SimpleScriptWitness SimpleScriptInMary (SScript script)) =
  Just $ ScriptInEra SimpleScriptInMary (SimpleScript script)
scriptWitnessScript (SimpleScriptWitness SimpleScriptInAlonzo (SScript script)) =
  Just $ ScriptInEra SimpleScriptInAlonzo (SimpleScript script)
scriptWitnessScript (SimpleScriptWitness SimpleScriptInBabbage (SScript script)) =
  Just $ ScriptInEra SimpleScriptInBabbage (SimpleScript script)
scriptWitnessScript (SimpleScriptWitness SimpleScriptInConway (SScript script)) =
  Just $ ScriptInEra SimpleScriptInConway (SimpleScript script)
scriptWitnessScript (PlutusScriptWitness langInEra version (PScript script) _ _ _) =
  Just $ ScriptInEra langInEra (PlutusScript version script)
scriptWitnessScript (SimpleScriptWitness _ (SReferenceScript _ _)) =
  Nothing
scriptWitnessScript (PlutusScriptWitness _ _ (PReferenceScript _ _) _ _ _) =
  Nothing

-- ----------------------------------------------------------------------------
-- The kind of witness to use, key (signature) or script
--

data Witness witctx era where
  KeyWitness
    :: KeyWitnessInCtx witctx
    -> Witness witctx era
  ScriptWitness
    :: ScriptWitnessInCtx witctx
    -> ScriptWitness witctx era
    -> Witness witctx era

deriving instance Eq (Witness witctx era)

deriving instance Show (Witness witctx era)

data KeyWitnessInCtx witctx where
  KeyWitnessForSpending :: KeyWitnessInCtx WitCtxTxIn
  KeyWitnessForStakeAddr :: KeyWitnessInCtx WitCtxStake

data ScriptWitnessInCtx witctx where
  ScriptWitnessForSpending :: ScriptWitnessInCtx WitCtxTxIn
  ScriptWitnessForMinting :: ScriptWitnessInCtx WitCtxMint
  ScriptWitnessForStakeAddr :: ScriptWitnessInCtx WitCtxStake

deriving instance Eq (KeyWitnessInCtx witctx)

deriving instance Show (KeyWitnessInCtx witctx)

deriving instance Eq (ScriptWitnessInCtx witctx)

deriving instance Show (ScriptWitnessInCtx witctx)

class IsScriptWitnessInCtx ctx where
  scriptWitnessInCtx :: ScriptWitnessInCtx ctx

instance IsScriptWitnessInCtx WitCtxTxIn where
  scriptWitnessInCtx = ScriptWitnessForSpending

instance IsScriptWitnessInCtx WitCtxMint where
  scriptWitnessInCtx = ScriptWitnessForMinting

instance IsScriptWitnessInCtx WitCtxStake where
  scriptWitnessInCtx = ScriptWitnessForStakeAddr

-- ----------------------------------------------------------------------------
-- Script execution units
--

-- | The units for how long a script executes for and how much memory it uses.
-- This is used to declare the resources used by a particular use of a script.
--
-- This type is also used to describe the limits for the maximum overall
-- execution units per transaction or per block.
data ExecutionUnits
  = ExecutionUnits
  { executionSteps :: Natural
  -- ^ This corresponds roughly to the time to execute a script.
  , executionMemory :: Natural
  -- ^ This corresponds roughly to the peak memory used during script
  -- execution.
  }
  deriving (Eq, Show)

instance ToCBOR ExecutionUnits where
  toCBOR ExecutionUnits{executionSteps, executionMemory} =
    CBOR.encodeListLen 2
      <> toCBOR executionSteps
      <> toCBOR executionMemory

instance FromCBOR ExecutionUnits where
  fromCBOR = do
    CBOR.enforceSize "ExecutionUnits" 2
    ExecutionUnits
      <$> fromCBOR
      <*> fromCBOR

instance ToJSON ExecutionUnits where
  toJSON ExecutionUnits{executionSteps, executionMemory} =
    object
      [ "steps" .= executionSteps
      , "memory" .= executionMemory
      ]

instance FromJSON ExecutionUnits where
  parseJSON =
    Aeson.withObject "ExecutionUnits" $ \o ->
      ExecutionUnits
        <$> o .: "steps"
        <*> o .: "memory"

toAlonzoExUnits :: ExecutionUnits -> Alonzo.ExUnits
toAlonzoExUnits ExecutionUnits{executionSteps, executionMemory} =
  Alonzo.ExUnits
    { Alonzo.exUnitsSteps = executionSteps
    , Alonzo.exUnitsMem = executionMemory
    }

fromAlonzoExUnits :: Alonzo.ExUnits -> ExecutionUnits
fromAlonzoExUnits Alonzo.ExUnits{Alonzo.exUnitsSteps, Alonzo.exUnitsMem} =
  ExecutionUnits
    { executionSteps = exUnitsSteps
    , executionMemory = exUnitsMem
    }

-- ----------------------------------------------------------------------------
-- Alonzo mediator pattern
--

pattern PlutusScriptBinary :: Plutus.PlutusLanguage l => ShortByteString -> Plutus.Plutus l
pattern PlutusScriptBinary script = Plutus.Plutus (Plutus.PlutusBinary script)

{-# COMPLETE PlutusScriptBinary #-}

-- ----------------------------------------------------------------------------
-- Script Hash
--

-- | We have this type separate from the 'Hash' type to avoid the script
-- hash type being parametrised by the era. The representation is era
-- independent, and there are many places where we want to use a script
-- hash where we don't want things to be era-parametrised.
newtype ScriptHash = ScriptHash (Shelley.ScriptHash StandardCrypto)
  deriving stock (Eq, Ord)
  deriving (Show, IsString) via UsingRawBytesHex ScriptHash
  deriving (ToJSON, FromJSON) via UsingRawBytesHex ScriptHash

instance HasTypeProxy ScriptHash where
  data AsType ScriptHash = AsScriptHash
  proxyToAsType _ = AsScriptHash

instance SerialiseAsRawBytes ScriptHash where
  serialiseToRawBytes (ScriptHash (Shelley.ScriptHash h)) =
    Crypto.hashToBytes h

  deserialiseFromRawBytes AsScriptHash bs =
    maybeToRight (SerialiseAsRawBytesError "Unable to deserialise ScriptHash") $
      ScriptHash . Shelley.ScriptHash <$> Crypto.hashFromBytes bs

hashScript :: Script lang -> ScriptHash
hashScript (SimpleScript s) =
  -- We convert to the Allegra-era version specifically and hash that.
  -- Later ledger eras have to be compatible anyway.
  ScriptHash
    . Ledger.hashScript @(ShelleyLedgerEra AllegraEra)
    . (toAllegraTimelock :: SimpleScript -> Timelock.Timelock (ShelleyLedgerEra AllegraEra))
    $ s
hashScript (PlutusScript PlutusScriptV1 (PlutusScriptSerialised script)) =
  -- For Plutus V1, we convert to the Alonzo-era version specifically and
  -- hash that. Later ledger eras have to be compatible anyway.
  ScriptHash
    . Ledger.hashScript @(ShelleyLedgerEra AlonzoEra)
    . Alonzo.PlutusScript
    . Alonzo.AlonzoPlutusV1
    . Plutus.Plutus
    $ Plutus.PlutusBinary script
hashScript (PlutusScript PlutusScriptV2 (PlutusScriptSerialised script)) =
  ScriptHash
    . Ledger.hashScript @(ShelleyLedgerEra BabbageEra)
    . Alonzo.PlutusScript
    . Babbage.BabbagePlutusV2
    . Plutus.Plutus
    $ Plutus.PlutusBinary script
hashScript (PlutusScript PlutusScriptV3 (PlutusScriptSerialised script)) =
  ScriptHash
    . Ledger.hashScript @(ShelleyLedgerEra ConwayEra)
    . Alonzo.PlutusScript
    . Conway.ConwayPlutusV3
    . Plutus.Plutus
    $ Plutus.PlutusBinary script

toShelleyScriptHash :: ScriptHash -> Shelley.ScriptHash StandardCrypto
toShelleyScriptHash (ScriptHash h) = h

fromShelleyScriptHash :: Shelley.ScriptHash StandardCrypto -> ScriptHash
fromShelleyScriptHash = ScriptHash

-- ----------------------------------------------------------------------------
-- The simple script language
--

data SimpleScript
  = RequireSignature !(Hash PaymentKey)
  | RequireTimeBefore !SlotNo
  | RequireTimeAfter !SlotNo
  | RequireAllOf ![SimpleScript]
  | RequireAnyOf ![SimpleScript]
  | RequireMOf !Int ![SimpleScript]
  deriving (Eq, Show)

-- ----------------------------------------------------------------------------
-- The Plutus script language
--

-- | Plutus scripts.
--
-- Note that Plutus scripts have a binary serialisation but no JSON
-- serialisation.
data PlutusScript lang where
  PlutusScriptSerialised :: ShortByteString -> PlutusScript lang
  deriving stock (Eq, Ord)
  deriving stock Show -- TODO: would be nice to use via UsingRawBytesHex
  -- however that adds an awkward HasTypeProxy lang =>
  -- constraint to other Show instances elsewhere
  deriving (ToCBOR, FromCBOR) via (UsingRawBytes (PlutusScript lang))
  deriving anyclass SerialiseAsCBOR

instance HasTypeProxy lang => HasTypeProxy (PlutusScript lang) where
  data AsType (PlutusScript lang) = AsPlutusScript (AsType lang)
  proxyToAsType _ = AsPlutusScript (proxyToAsType (Proxy :: Proxy lang))

instance HasTypeProxy lang => SerialiseAsRawBytes (PlutusScript lang) where
  serialiseToRawBytes (PlutusScriptSerialised sbs) = SBS.fromShort sbs

  deserialiseFromRawBytes (AsPlutusScript _) bs =
    -- TODO alonzo: validate the script syntax and fail decoding if invalid
    Right (PlutusScriptSerialised (SBS.toShort bs))

instance IsPlutusScriptLanguage lang => HasTextEnvelope (PlutusScript lang) where
  textEnvelopeType _ =
    case plutusScriptVersion :: PlutusScriptVersion lang of
      PlutusScriptV1 -> "PlutusScriptV1"
      PlutusScriptV2 -> "PlutusScriptV2"
      PlutusScriptV3 -> "PlutusScriptV3"

-- | Smart-constructor for 'ScriptLanguageInEra' to write functions
-- manipulating scripts that do not commit to a particular era.
class HasScriptLanguageInEra lang era where
  scriptLanguageInEra :: ScriptLanguageInEra lang era

instance HasScriptLanguageInEra PlutusScriptV1 AlonzoEra where
  scriptLanguageInEra = PlutusScriptV1InAlonzo

instance HasScriptLanguageInEra PlutusScriptV1 BabbageEra where
  scriptLanguageInEra = PlutusScriptV1InBabbage

instance HasScriptLanguageInEra PlutusScriptV2 BabbageEra where
  scriptLanguageInEra = PlutusScriptV2InBabbage

instance HasScriptLanguageInEra PlutusScriptV1 ConwayEra where
  scriptLanguageInEra = PlutusScriptV1InConway

instance HasScriptLanguageInEra PlutusScriptV2 ConwayEra where
  scriptLanguageInEra = PlutusScriptV2InConway

instance HasScriptLanguageInEra PlutusScriptV3 ConwayEra where
  scriptLanguageInEra = PlutusScriptV3InConway

class ToAlonzoScript lang era where
  toLedgerScript
    :: PlutusScript lang
    -> Conway.AlonzoScript (ShelleyLedgerEra era)

instance ToAlonzoScript PlutusScriptV1 BabbageEra where
  toLedgerScript (PlutusScriptSerialised bytes) =
    Conway.PlutusScript $ Conway.BabbagePlutusV1 $ Plutus.Plutus $ Plutus.PlutusBinary bytes

instance ToAlonzoScript PlutusScriptV2 BabbageEra where
  toLedgerScript (PlutusScriptSerialised bytes) =
    Conway.PlutusScript $ Conway.BabbagePlutusV2 $ Plutus.Plutus $ Plutus.PlutusBinary bytes

instance ToAlonzoScript PlutusScriptV1 ConwayEra where
  toLedgerScript (PlutusScriptSerialised bytes) =
    Conway.PlutusScript $ Conway.ConwayPlutusV1 $ Plutus.Plutus $ Plutus.PlutusBinary bytes

instance ToAlonzoScript PlutusScriptV2 ConwayEra where
  toLedgerScript (PlutusScriptSerialised bytes) =
    Conway.PlutusScript $ Conway.ConwayPlutusV2 $ Plutus.Plutus $ Plutus.PlutusBinary bytes

instance ToAlonzoScript PlutusScriptV3 ConwayEra where
  toLedgerScript (PlutusScriptSerialised bytes) =
    Conway.PlutusScript $ Conway.ConwayPlutusV3 $ Plutus.Plutus $ Plutus.PlutusBinary bytes

-- | An example Plutus script that always succeeds, irrespective of inputs.
--
-- For example, if one were to use this for a payment address then it would
-- allow anyone to spend from it.
--
-- The exact script depends on the context in which it is to be used.
examplePlutusScriptAlwaysSucceeds
  :: WitCtx witctx
  -> PlutusScript PlutusScriptV1
examplePlutusScriptAlwaysSucceeds =
  PlutusScriptSerialised
    . Plutus.alwaysSucceedingNAryFunction
    . scriptArityForWitCtx

-- | An example Plutus script that always fails, irrespective of inputs.
--
-- For example, if one were to use this for a payment address then it would
-- be impossible for anyone to ever spend from it.
--
-- The exact script depends on the context in which it is to be used.
examplePlutusScriptAlwaysFails
  :: WitCtx witctx
  -> PlutusScript PlutusScriptV1
examplePlutusScriptAlwaysFails =
  PlutusScriptSerialised
    . Plutus.alwaysFailingNAryFunction
    . scriptArityForWitCtx

-- | The expected arity of the Plutus function, depending on the context in
-- which it is used.
--
-- The script inputs consist of
--
-- * the optional datum (for txins)
-- * the redeemer
-- * the Plutus representation of the tx and environment
scriptArityForWitCtx :: WitCtx witctx -> Natural
scriptArityForWitCtx WitCtxTxIn = 3
scriptArityForWitCtx WitCtxMint = 2
scriptArityForWitCtx WitCtxStake = 2

-- ----------------------------------------------------------------------------
-- Conversion functions
--

toShelleyScript :: ScriptInEra era -> Ledger.Script (ShelleyLedgerEra era)
toShelleyScript (ScriptInEra langInEra (SimpleScript script)) =
  case langInEra of
    SimpleScriptInShelley -> either (error . show) id (toShelleyMultiSig script)
    SimpleScriptInAllegra -> toAllegraTimelock script
    SimpleScriptInMary -> toAllegraTimelock script
    SimpleScriptInAlonzo -> Alonzo.TimelockScript (toAllegraTimelock script)
    SimpleScriptInBabbage -> Alonzo.TimelockScript (toAllegraTimelock script)
    SimpleScriptInConway -> Alonzo.TimelockScript (toAllegraTimelock script)
toShelleyScript
  ( ScriptInEra
      langInEra
      ( PlutusScript
          PlutusScriptV1
          (PlutusScriptSerialised script)
        )
    ) =
    case langInEra of
      PlutusScriptV1InAlonzo ->
        Alonzo.PlutusScript . Alonzo.AlonzoPlutusV1 . Plutus.Plutus $ Plutus.PlutusBinary script
      PlutusScriptV1InBabbage ->
        Alonzo.PlutusScript . Babbage.BabbagePlutusV1 . Plutus.Plutus $ Plutus.PlutusBinary script
      PlutusScriptV1InConway ->
        Alonzo.PlutusScript . Conway.ConwayPlutusV1 . Plutus.Plutus $ Plutus.PlutusBinary script
toShelleyScript
  ( ScriptInEra
      langInEra
      ( PlutusScript
          PlutusScriptV2
          (PlutusScriptSerialised script)
        )
    ) =
    case langInEra of
      PlutusScriptV2InBabbage ->
        Alonzo.PlutusScript . Babbage.BabbagePlutusV2 . Plutus.Plutus $ Plutus.PlutusBinary script
      PlutusScriptV2InConway ->
        Alonzo.PlutusScript . Conway.ConwayPlutusV2 . Plutus.Plutus $ Plutus.PlutusBinary script
toShelleyScript
  ( ScriptInEra
      langInEra
      ( PlutusScript
          PlutusScriptV3
          (PlutusScriptSerialised script)
        )
    ) =
    case langInEra of
      PlutusScriptV3InConway ->
        Alonzo.PlutusScript . Conway.ConwayPlutusV3 . Plutus.Plutus $ Plutus.PlutusBinary script

fromShelleyBasedScript
  :: ShelleyBasedEra era
  -> Ledger.Script (ShelleyLedgerEra era)
  -> ScriptInEra era
fromShelleyBasedScript sbe script =
  case sbe of
    ShelleyBasedEraShelley ->
      ScriptInEra SimpleScriptInShelley
        . SimpleScript
        $ fromShelleyMultiSig script
    ShelleyBasedEraAllegra ->
      ScriptInEra SimpleScriptInAllegra
        . SimpleScript
        $ fromAllegraTimelock script
    ShelleyBasedEraMary ->
      ScriptInEra SimpleScriptInMary
        . SimpleScript
        $ fromAllegraTimelock script
    ShelleyBasedEraAlonzo ->
      case script of
        Alonzo.PlutusScript (Alonzo.AlonzoPlutusV1 (PlutusScriptBinary s)) ->
          ScriptInEra PlutusScriptV1InAlonzo
            . PlutusScript PlutusScriptV1
            $ PlutusScriptSerialised s
        Alonzo.TimelockScript s ->
          ScriptInEra SimpleScriptInAlonzo
            . SimpleScript
            $ fromAllegraTimelock s
    ShelleyBasedEraBabbage ->
      case script of
        Alonzo.PlutusScript plutusV ->
          case plutusV of
            Babbage.BabbagePlutusV1 (PlutusScriptBinary s) ->
              ScriptInEra PlutusScriptV1InBabbage
                . PlutusScript PlutusScriptV1
                $ PlutusScriptSerialised s
            Babbage.BabbagePlutusV2 (PlutusScriptBinary s) ->
              ScriptInEra PlutusScriptV2InBabbage
                . PlutusScript PlutusScriptV2
                $ PlutusScriptSerialised s
        Alonzo.TimelockScript s ->
          ScriptInEra SimpleScriptInBabbage
            . SimpleScript
            $ fromAllegraTimelock s
    ShelleyBasedEraConway ->
      case script of
        Alonzo.PlutusScript plutusV ->
          case plutusV of
            Conway.ConwayPlutusV1 (PlutusScriptBinary s) ->
              ScriptInEra PlutusScriptV1InConway
                . PlutusScript PlutusScriptV1
                $ PlutusScriptSerialised s
            Conway.ConwayPlutusV2 (PlutusScriptBinary s) ->
              ScriptInEra PlutusScriptV2InConway
                . PlutusScript PlutusScriptV2
                $ PlutusScriptSerialised s
            Conway.ConwayPlutusV3 (PlutusScriptBinary s) ->
              ScriptInEra PlutusScriptV3InConway
                . PlutusScript PlutusScriptV3
                $ PlutusScriptSerialised s
        Alonzo.TimelockScript s ->
          ScriptInEra SimpleScriptInConway
            . SimpleScript
            $ fromAllegraTimelock s

data MultiSigError = MultiSigErrorTimelockNotsupported deriving Show

-- | Conversion for the 'Shelley.MultiSig' language used by the Shelley era.
toShelleyMultiSig
  :: SimpleScript
  -> Either MultiSigError (Shelley.MultiSig (ShelleyLedgerEra ShelleyEra))
toShelleyMultiSig = go
 where
  go :: SimpleScript -> Either MultiSigError (Shelley.MultiSig (ShelleyLedgerEra ShelleyEra))
  go (RequireSignature (PaymentKeyHash kh)) =
    return $ Shelley.RequireSignature (Shelley.asWitness kh)
  go (RequireAllOf s) = mapM go s <&> Shelley.RequireAllOf . Seq.fromList
  go (RequireAnyOf s) = mapM go s <&> Shelley.RequireAnyOf . Seq.fromList
  go (RequireMOf m s) = mapM go s <&> Shelley.RequireMOf m . Seq.fromList
  go _ = Left MultiSigErrorTimelockNotsupported

-- | Conversion for the 'Shelley.MultiSig' language used by the Shelley era.
fromShelleyMultiSig :: Shelley.MultiSig (ShelleyLedgerEra ShelleyEra) -> SimpleScript
fromShelleyMultiSig = go
 where
  go (Shelley.RequireSignature kh) =
    RequireSignature
      (PaymentKeyHash (Shelley.coerceKeyRole kh))
  go (Shelley.RequireAllOf s) = RequireAllOf (map go $ toList s)
  go (Shelley.RequireAnyOf s) = RequireAnyOf (map go $ toList s)
  go (Shelley.RequireMOf m s) = RequireMOf m (map go $ toList s)
  go _ = error ""

-- | Conversion for the 'Timelock.Timelock' language that is shared between the
-- Allegra and Mary eras.
toAllegraTimelock
  :: forall era
   . ( Allegra.AllegraEraScript era
     , EraCrypto era ~ StandardCrypto
     , Ledger.NativeScript era ~ Allegra.Timelock era
     )
  => SimpleScript -> Ledger.NativeScript era
toAllegraTimelock = go
 where
  go :: SimpleScript -> Timelock.Timelock era
  go (RequireSignature (PaymentKeyHash kh)) =
    Shelley.RequireSignature (Shelley.asWitness kh)
  go (RequireAllOf s) = Shelley.RequireAllOf (Seq.fromList (map go s))
  go (RequireAnyOf s) = Shelley.RequireAnyOf (Seq.fromList (map go s))
  go (RequireMOf m s) = Shelley.RequireMOf m (Seq.fromList (map go s))
  go (RequireTimeBefore t) = Allegra.RequireTimeExpire t
  go (RequireTimeAfter t) = Allegra.RequireTimeStart t

-- | Conversion for the 'Timelock.Timelock' language that is shared between the
-- Allegra and Mary eras.
fromAllegraTimelock
  :: (Allegra.AllegraEraScript era, EraCrypto era ~ StandardCrypto)
  => Ledger.NativeScript era -> SimpleScript
fromAllegraTimelock = go
 where
  go (Shelley.RequireSignature kh) = RequireSignature (PaymentKeyHash (Shelley.coerceKeyRole kh))
  go (Allegra.RequireTimeExpire t) = RequireTimeBefore t
  go (Allegra.RequireTimeStart t) = RequireTimeAfter t
  go (Shelley.RequireAllOf s) = RequireAllOf (map go (toList s))
  go (Shelley.RequireAnyOf s) = RequireAnyOf (map go (toList s))
  go (Shelley.RequireMOf i s) = RequireMOf i (map go (toList s))

-- ----------------------------------------------------------------------------
-- JSON serialisation
--

-- Remember that Plutus scripts do not have a JSON syntax, and so do not have
-- and JSON instances. The only JSON format they support is via the
-- HasTextEnvelope class which just wraps the binary format.
--
-- Because of this the 'Script' type also does not have any JSON instances, but
-- the 'SimpleScript' type does.

instance ToJSON SimpleScript where
  toJSON (RequireSignature pKeyHash) =
    object
      [ "type" .= String "sig"
      , "keyHash" .= serialiseToRawBytesHexText pKeyHash
      ]
  toJSON (RequireTimeBefore slot) =
    object
      [ "type" .= String "before"
      , "slot" .= slot
      ]
  toJSON (RequireTimeAfter slot) =
    object
      [ "type" .= String "after"
      , "slot" .= slot
      ]
  toJSON (RequireAnyOf reqScripts) =
    object ["type" .= String "any", "scripts" .= map toJSON reqScripts]
  toJSON (RequireAllOf reqScripts) =
    object ["type" .= String "all", "scripts" .= map toJSON reqScripts]
  toJSON (RequireMOf reqNum reqScripts) =
    object
      [ "type" .= String "atLeast"
      , "required" .= reqNum
      , "scripts" .= map toJSON reqScripts
      ]

instance FromJSON SimpleScript where
  parseJSON = parseSimpleScript

parseSimpleScript :: Value -> Aeson.Parser SimpleScript
parseSimpleScript v =
  parseScriptSig v
    <|> parseScriptBefore v
    <|> parseScriptAfter v
    <|> parseScriptAny v
    <|> parseScriptAll v
    <|> parseScriptAtLeast v

parseScriptAny :: Value -> Aeson.Parser SimpleScript
parseScriptAny =
  Aeson.withObject "any" $ \obj -> do
    t <- obj .: "type"
    case t :: Text of
      "any" -> do
        vs <- obj .: "scripts"
        RequireAnyOf <$> gatherSimpleScriptTerms vs
      _ -> fail "\"any\" script value not found"

parseScriptAll :: Value -> Aeson.Parser SimpleScript
parseScriptAll =
  Aeson.withObject "all" $ \obj -> do
    t <- obj .: "type"
    case t :: Text of
      "all" -> do
        vs <- obj .: "scripts"
        RequireAllOf <$> gatherSimpleScriptTerms vs
      _ -> fail "\"all\" script value not found"

parseScriptAtLeast :: Value -> Aeson.Parser SimpleScript
parseScriptAtLeast =
  Aeson.withObject "atLeast" $ \obj -> do
    v <- obj .: "type"
    case v :: Text of
      "atLeast" -> do
        r <- obj .: "required"
        vs <- obj .: "scripts"
        case r of
          Number sci ->
            case toBoundedInteger sci of
              Just reqInt ->
                do
                  scripts <- gatherSimpleScriptTerms vs
                  let numScripts = length scripts
                  when
                    (reqInt > numScripts)
                    ( fail $
                        "Required number of script signatures exceeds the number of scripts."
                          <> " Required number: "
                          <> show reqInt
                          <> " Number of scripts: "
                          <> show numScripts
                    )
                  return $ RequireMOf reqInt scripts
              Nothing ->
                fail $
                  "Error in \"required\" key: "
                    <> show sci
                    <> " is not a valid Int"
          _ -> fail "\"required\" value should be an integer"
      _ -> fail "\"atLeast\" script value not found"

gatherSimpleScriptTerms :: Vector Value -> Aeson.Parser [SimpleScript]
gatherSimpleScriptTerms = mapM parseSimpleScript . toList

parseScriptSig :: Value -> Aeson.Parser SimpleScript
parseScriptSig =
  Aeson.withObject "sig" $ \obj -> do
    v <- obj .: "type"
    case v :: Text of
      "sig" -> do
        k <- obj .: "keyHash"
        RequireSignature <$> parsePaymentKeyHash k
      _ -> fail "\"sig\" script value not found"

parseScriptBefore :: Value -> Aeson.Parser SimpleScript
parseScriptBefore =
  Aeson.withObject "before" $ \obj -> do
    v <- obj .: "type"
    case v :: Text of
      "before" -> RequireTimeBefore <$> obj .: "slot"
      _ -> fail "\"before\" script value not found"

parseScriptAfter :: Value -> Aeson.Parser SimpleScript
parseScriptAfter =
  Aeson.withObject "after" $ \obj -> do
    v <- obj .: "type"
    case v :: Text of
      "after" -> RequireTimeAfter <$> obj .: "slot"
      _ -> fail "\"after\" script value not found"

parsePaymentKeyHash :: Text -> Aeson.Parser (Hash PaymentKey)
parsePaymentKeyHash =
  failEitherWith
    (\e -> "Error deserialising payment key hash: " ++ displayError e)
    . deserialiseFromRawBytesHex (AsHash AsPaymentKey)
    . Text.encodeUtf8

-- ----------------------------------------------------------------------------
-- Reference scripts
--

-- | A reference scripts is a script that can exist at a transaction output. This greatly
-- reduces the size of transactions that use scripts as the script no longer
-- has to be added to the transaction, they can now be referenced via a transaction output.
data ReferenceScript era where
  ReferenceScript
    :: BabbageEraOnwards era
    -> ScriptInAnyLang
    -> ReferenceScript era
  ReferenceScriptNone :: ReferenceScript era

deriving instance Eq (ReferenceScript era)

deriving instance Show (ReferenceScript era)

deriving instance Typeable (ReferenceScript era)

instance IsCardanoEra era => ToJSON (ReferenceScript era) where
  toJSON (ReferenceScript _ s) = object ["referenceScript" .= s]
  toJSON ReferenceScriptNone = Aeson.Null

instance IsCardanoEra era => FromJSON (ReferenceScript era) where
  parseJSON = Aeson.withObject "ReferenceScript" $ \o ->
    caseByronToAlonzoOrBabbageEraOnwards
      (const (pure ReferenceScriptNone))
      (\w -> ReferenceScript w <$> o .: "referenceScript")
      (cardanoEra :: CardanoEra era)

refScriptToShelleyScript
  :: ShelleyBasedEra era
  -> ReferenceScript era
  -> StrictMaybe (Ledger.Script (ShelleyLedgerEra era))
refScriptToShelleyScript era (ReferenceScript _ s) =
  case toScriptInEra era s of
    Just sInEra -> SJust $ toShelleyScript sInEra
    Nothing -> SNothing
refScriptToShelleyScript _ ReferenceScriptNone = SNothing

fromShelleyScriptToReferenceScript
  :: ShelleyBasedEra era -> Ledger.Script (ShelleyLedgerEra era) -> ReferenceScript era
fromShelleyScriptToReferenceScript sbe script =
  scriptInEraToRefScript $ fromShelleyBasedScript sbe script

scriptInEraToRefScript :: ScriptInEra era -> ReferenceScript era
scriptInEraToRefScript sIne@(ScriptInEra _ s) =
  caseShelleyToAlonzoOrBabbageEraOnwards
    (const ReferenceScriptNone)
    (\w -> ReferenceScript w $ toScriptInAnyLang s) -- Any script can be a reference script
    (eraOfScriptInEra sIne)

-- Helpers

textEnvelopeToScript :: TextEnvelope -> Either TextEnvelopeError ScriptInAnyLang
textEnvelopeToScript = deserialiseFromTextEnvelopeAnyOf textEnvTypes
 where
  textEnvTypes :: [FromSomeType HasTextEnvelope ScriptInAnyLang]
  textEnvTypes =
    [ FromSomeType
        (AsScript AsSimpleScript)
        (ScriptInAnyLang SimpleScriptLanguage)
    , FromSomeType
        (AsScript AsPlutusScriptV1)
        (ScriptInAnyLang (PlutusScriptLanguage PlutusScriptV1))
    , FromSomeType
        (AsScript AsPlutusScriptV2)
        (ScriptInAnyLang (PlutusScriptLanguage PlutusScriptV2))
    , FromSomeType
        (AsScript AsPlutusScriptV3)
        (ScriptInAnyLang (PlutusScriptLanguage PlutusScriptV3))
    ]
