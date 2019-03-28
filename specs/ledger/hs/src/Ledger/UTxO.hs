{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE TypeFamilies #-}

module Ledger.UTxO where

import Control.State.Transition
import qualified Data.ByteArray as BA
import Data.List (find)
import qualified Data.List as List
import qualified Data.Map.Strict as Map
import Data.Maybe (isJust, fromMaybe)
import Ledger.Core hiding ((◁), (⋪), (∪))
import Numeric.Natural (Natural)
import Data.Map.Strict (Map)
import qualified Crypto.Hash as Crypto
import qualified Data.ByteString.Char8 as BS

-- |A unique ID of a transaction, which is computable from the transaction.
newtype TxId = TxId { getTxId :: Hash }
  deriving (Show, Eq, Ord)

-- |The input of a UTxO.
--
--     * __TODO__ - is it okay to use list indices instead of implementing the Ix Type?
data TxIn id = TxIn id Natural deriving (Show, Eq, Ord)

-- |The output of a UTxO.
data TxOut = TxOut Addr Value deriving (Show, Eq, Ord)

-- |The unspent transaction outputs.
newtype UTxO id = UTxO (Map (TxIn id) TxOut) deriving (Show, Eq)

-- |A raw transaction
data Tx id = Tx { txid :: id
                , inputs  :: [TxIn id]
                , outputs :: [TxOut]
                } deriving (Show, Ord)

instance Eq id => Eq (Tx id) where
  (Tx _ ins outs) == (Tx _ ins' outs') = ins == ins' && outs == outs'

-- -- |Compute the id of a transaction.
-- class IsTxId id where
--   txid :: Tx id -> id

-- instance IsTxId TxId where
--   txid = TxId . hash

-- |Compute the UTxO inputs of a transaction.
txins :: Tx id -> [TxIn id]
txins = inputs

-- |Compute the UTxO outputs of a transaction.
txouts :: Ord id => Tx id -> UTxO id
txouts tx = UTxO $ Map.fromList
  [ (TxIn transId idx, out) | (out, idx) <- zip (outputs tx) [0 ..] ]
  where transId = txid tx

txfee :: Tx id -> Value
txfee _ = Value 0

-- |Domain restriction
--
--     * __TODO__ - better symbol?
(◁) :: Ord id => [TxIn id]-> UTxO id -> UTxO id
ins ◁ (UTxO utxo) = UTxO $ Map.filterWithKey (\k _ -> k `elem` ins) utxo

(<|) :: Ord id => [TxIn id] -> UTxO id -> UTxO id
(<|) = (◁)

-- |Domain exclusion
--
(⋪) :: Ord id => [TxIn id] -> UTxO id -> UTxO id
ins ⋪ (UTxO utxo) =
  UTxO $ Map.filterWithKey (\k _ -> k `notElem` ins) utxo

-- |Combine two collections of UTxO.
--
--     * TODO - Should we return 'Maybe UTxO' so that we can return
-- Nothing when the collections are not disjoint?
(∪) :: Ord id => UTxO id -> UTxO id -> UTxO id
(UTxO a) ∪ (UTxO b) = UTxO $ Map.union a b

-- |Determine the total balance contained in the UTxO.
balance :: UTxO id -> Value
balance (UTxO utxo) = Map.foldl' addValues mempty utxo
  where addValues b (TxOut _ a) = b <> a

instance Ledger.Core.HasHash (Tx TxId) where
  hash = Crypto.hash

instance Show id => BA.ByteArrayAccess (Tx id) where
  length        = BA.length . BS.pack . show
  withByteArray = BA.withByteArray . BS.pack  . show

---------------------------------------------------------------------------------
-- UTxO transitions
---------------------------------------------------------------------------------

data UTxOEnv id = UTxOEnv { utxo0 :: UTxO id
                          , pps   :: ProtocolConstants id
                          }

newtype ProtocolConstants id = ProtocolConstants
  { pcMinFee :: Tx id -> Value }

-- | UTXO transition system
data UTXO id

instance Ord id => STS (UTXO id) where
  type State (UTXO id) = UTxO id
  type Signal (UTXO id) = Tx id
  type Environment (UTXO id) = UTxOEnv id
  data PredicateFailure (UTXO id)
    = BadInputs
    | FeeTooLow
    | IncreasedTotalBalance
    deriving (Eq, Show)

  initialRules =
    [ return (UTxO Map.empty) ]
  transitionRules = [ utxoInductive ]

utxoInductive :: Ord id => TransitionRule (UTXO id)
utxoInductive = do
  TRC (UTxOEnv _ pc, utxo, tx) <- judgmentContext
  balance (txouts tx)
    <> txfee tx
    == balance (txins tx ◁ utxo)
    ?! IncreasedTotalBalance
  pcMinFee pc tx <= txfee tx ?! FeeTooLow
  let unspentInputs (UTxO aUtxo) = Map.keys aUtxo
  txins tx `List.isSubsequenceOf` unspentInputs utxo ?! BadInputs
  return $ (txins tx ⋪ utxo) ∪ txouts tx

---------------------------------------------------------------------------------
-- UTxO transitions
---------------------------------------------------------------------------------

-- |Proof/Witness that a transaction is authorized by the given key holder.
data Wit id = Wit VKey (Sig (Tx id)) deriving (Show, Eq, Ord)

-- |A fully formed transaction.
--
--     * __TODO__ - Would it be better to name this type Tx, and rename Tx to TxBody?
data TxWits id = TxWits
                { body      :: Tx id
                , witnesses :: [Wit id]
                } deriving (Show, Eq)

-- |Create a witness for transaction
makeWitness :: KeyPair -> Tx id -> Wit id
makeWitness keys tx = Wit (vKey keys) (sign (sKey keys) tx)

makeTxWits :: Ord id => UTxO id -> Tx id -> TxWits id
makeTxWits (UTxO utxo) tx = TxWits
  { body      = tx
  , witnesses = wits
  }
 where
  getKey txin =
    let
      TxOut (Addr (VKey o)) _ =
        fromMaybe
            (error "witnessTransaction: Missing output for transaction input")
          $ Map.lookup txin utxo
    in KeyPair (SKey o) (VKey o)
  keys = getKey <$> inputs tx
  wits = makeWitness <$> keys <*> pure tx

-- | UTXO with witnessing
data UTXOW id

instance Ord id => STS (UTXOW id) where
  type State (UTXOW id) = UTxO id
  type Signal (UTXOW id) = TxWits id
  type Environment (UTXOW id) = UTxOEnv id
  data PredicateFailure (UTXOW id)
    = UtxoFailure (PredicateFailure (UTXO id))
    | InsufficientWitnesses
    deriving (Eq, Show)

  initialRules = [ return $ UTxO Map.empty ]
  transitionRules =
    [ do
        TRC (env, utxo, tw) <- judgmentContext
        witnessed tw utxo ?! InsufficientWitnesses
        res <- trans @(UTXO id) $ TRC (env, utxo, body tw)
        return res
    ]

instance Ord id => Embed (UTXO id) (UTXOW id) where
  wrapFailed = UtxoFailure

-- |Determine if a UTxO input is authorized by a given key.
authTxin :: Ord id => VKey -> TxIn id -> UTxO id -> Bool
authTxin key txin (UTxO utxo) = case Map.lookup txin utxo of
  Just (TxOut (Addr pay) _) -> key == pay
  _                         -> False

-- |Given a ledger state, determine if the UTxO witnesses in a given
-- transaction are sufficient.
-- TODO - should we only check for one witness for each unique input address?
witnessed :: Ord id => TxWits id -> UTxO id -> Bool
witnessed (TxWits tx wits) utxo =
  length wits == length ins && all (hasWitness wits) ins
 where
  ins = inputs tx
  hasWitness ws input =
    isJust $ find (isWitness tx input utxo) ws
  isWitness tx' input unspent (Wit key sig) =
    verify key tx' sig && authTxin key input unspent
