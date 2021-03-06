{-# LANGUAGE EmptyDataDecls #-}
{-# LANGUAGE TypeFamilies   #-}

module STS.Snap
  ( SNAP
  ) where

import qualified Data.Map                 as Map

import           Lens.Micro              ((^.), (&), (.~), (%~))

import           Coin
import           EpochBoundary
import           LedgerState
import           PParams
import           Slot
import           UTxO

import           Control.State.Transition

data SNAP

instance STS SNAP where
  type State SNAP = (SnapShots, UTxOState)
  type Signal SNAP = ()
  type Environment SNAP = (Epoch, PParams, DState, PState, BlocksMade)
  data PredicateFailure SNAP = FailureSNAP
                               deriving (Show, Eq)
  initialRules =
    [pure (emptySnapShots, UTxOState (UTxO Map.empty) (Coin 0) (Coin 0))]
  transitionRules = [snapTransition]

snapTransition :: TransitionRule SNAP
snapTransition = do
  TRC ((eNew, pparams, d, p, blocks), (s, u), _) <- judgmentContext
  let pooledStake = poolDistr (u ^. utxo) d p
  let slot = firstSlot eNew
  let oblg = obligation pparams (d ^. stKeys) (p ^. stPools) slot
  let decayed = (u ^. deposited) - oblg
  pure
    ( s & pstakeMark .~ pooledStake & pstakeSet .~ (s ^. pstakeMark) &
      pstakeGo .~ (s ^. pstakeSet) &
      poolsSS .~ (p ^. pParams) &
      blocksSS .~ blocks &
      feeSS .~ (u ^. fees) + decayed
    , u & deposited .~ oblg & fees %~ (+) decayed)
