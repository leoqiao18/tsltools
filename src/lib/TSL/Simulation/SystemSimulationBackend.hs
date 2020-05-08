-----------------------------------------------------------------------------
-- |
-- Module      :  TSL.Simulaton.SystemSimulationBackend
-- Maintainer  :  Philippe Heim (Heim@ProjectJARVIS.de)
--
-- The backend of the system simulation when playing againts a counter
-- strategy
--
-----------------------------------------------------------------------------

{-# LANGUAGE

    ViewPatterns
  , LambdaCase
  , RecordWildCards

  #-}

-----------------------------------------------------------------------------

module TSL.Simulation.SystemSimulationBackend
  ( EnvironmentCounterStrategy
  , SystemOption
  , SystemSimulation(..)
  , options
  , step
  , rewind
  , getLog
  , sanitize
  ) where

-----------------------------------------------------------------------------

import Control.Exception
  ( assert
  )

import TSL.Specification
  ( Specification(..)
  )

import TSL.SymbolTable
  ( stName
  )

import qualified Data.Set as Set
  ( filter
  )

import Data.Set as Set
  ( difference
  , fromList
  , isSubsetOf
  , map
  , powerSet
  , toList
  )

import TSL.Simulation.AigerSimulator
  ( NormCircuit
  , State
  , inputName
  , inputs
  , outputName
  , outputs
  , simStep
  )

import TSL.Simulation.FiniteTraceChecker
  ( FiniteTrace
  , append
  , violated
  )

import qualified TSL.Simulation.FiniteTraceChecker as FTC
  ( rewind
  )

import TSL.Logic
  ( Formula(..)
  , PredicateTerm
  , SignalTerm(..)
  )

import TSL.FormulaUtils
  ( getOutputs
  , getPredicates
  )

import TSL.ToString
  ( predicateTermToString
  )

------------------------------------------------------------------------------

-- | A environment startegy is a circuit with predicate evaluations as
-- outputs and updates as inputs

type EnvironmentCounterStrategy =
  NormCircuit (String, SignalTerm String) (PredicateTerm String)

------------------------------------------------------------------------------

-- | The option of the system is a list of update choice

type SystemOption = [(String, SignalTerm String)]

------------------------------------------------------------------------------

type Witness = [Formula String]

------------------------------------------------------------------------------

-- | A system simulation consists of the environments counter
-- strategy, the respective specification, the stack of the startegies
-- state, the trace and a logging trace

data SystemSimulation =
  SystemSimulation
    { counterStrategy :: EnvironmentCounterStrategy
    , specification :: Specification
    , stateStack :: [State]
    , trace :: FiniteTrace String
    , logTrace :: [(SystemOption, [(PredicateTerm String, Bool)])]
    }

-----------------------------------------------------------------------------

-- | Gives all options of a simulation and a list of TSLFormulas (Witness)
-- that would be violated

options
  :: SystemSimulation
  -> [(SystemOption, Witness, [(PredicateTerm String, Bool)])]

options sim@SystemSimulation {counterStrategy = ct} =
  let
    options = possibleOptions ct
    steps = fmap (step sim) options
    witnesses = fmap (violated . trace . fst) steps
    evaluations = fmap snd steps
  in
    zip3 options witnesses evaluations

  where
    possibleOptions
      :: EnvironmentCounterStrategy -> [SystemOption]

    possibleOptions cst =
      let
        allUpdates = [inputName cst i | i <- inputs cst]
        cells = removeDoubles $ fmap fst allUpdates
        allCombinations = Set.map toList $ powerSet $ fromList allUpdates
        filteredCombinations =
          toList $ Set.filter (unique . (fmap fst)) $ allCombinations
       in
        removeDoubles $
          fmap (removeDoubles . (extendUpdates cells)) filteredCombinations

    unique = \case
      []   -> True
      c:cr -> (not (elem c cr)) && unique cr

    extendUpdates cells updates =
      foldl
        (\upds c ->
           if all ((/= c) . fst) upds
             then (c, Signal c) : upds
             else upds)
        updates
        cells

    removeDoubles
      :: Ord a => [a] -> [a]

    removeDoubles =
      Set.toList . Set.fromList

-----------------------------------------------------------------------------

-- | Given an possible action option, simulate one step and calculate
-- the predicate evaluations
--
-- ASSUMPTION: The option should be complete, i.e. on a higher level
-- for every cell in the formula, the circuit can update on of these
-- cells, and the preidcates have to match (can be checked using
-- sanitize)

step
  :: SystemSimulation -> SystemOption
  -> (SystemSimulation, [(PredicateTerm String, Bool)])

step sim@SystemSimulation {..} updates =
  let
    -- The input for the c-strat circuit
    input = \i -> elem (inputName counterStrategy i) updates

    -- The c-strat simulation step
    (q, output) = simStep counterStrategy (head stateStack) input

    -- The predicate evaluation generated out of the output
    eval =
      [ (outputName counterStrategy o, output o)
      | o <- outputs counterStrategy
      ]

    newTrace =
      append
        trace
        (\c -> findFirst (== c) updates)
        (\p -> findFirst (== p) eval)

    newLog = (updates, eval) : logTrace
  in
    ( sim
        { stateStack = q : stateStack
        , trace = newTrace
        , logTrace = newLog
        }
    , eval
    )

  where
    findFirst
      :: (a -> Bool) -> [(a, b)] -> b

    findFirst p = \case
      -- can't happend iff the simulation is sanitized
      []       -> assert False undefined
      -- otherwise
      (a,b):xr
        | p a       -> b
        | otherwise -> findFirst p xr

-----------------------------------------------------------------------------

-- | Rewind steps the simulation one step back

rewind
  :: SystemSimulation -> SystemSimulation

rewind sim@SystemSimulation{..} =
  sim
    { stateStack =
        case stateStack of
          [] -> assert False undefined -- There is always an inital state
          [init] -> [init]
          _:sr -> sr
    , trace = FTC.rewind trace
    , logTrace =
        case logTrace of
          [] -> []
          _:lr -> lr
    }

-----------------------------------------------------------------------------

-- | Sanitize the simulation

sanitize
  :: SystemSimulation -> Maybe String

sanitize SystemSimulation{counterStrategy = cst, specification = spec} =
  let
    specForm = Implies (And $ assumptionsStr spec) (And $ guaranteesStr spec)
    specUpatedCells = getOutputs specForm
    specPredicates = getPredicates specForm

    strategyUpdatedCells =
      fromList $ fmap fst [inputName cst o | o <- inputs cst]
    strategyPredicates = fromList $ [outputName cst o | o <- outputs cst]

    errorMsgCells =
      "Simulator: Specification does not match the " ++
      "strategy as the following cells differ:  " ++
      concatMap
        (++ " ")
        (toList $ difference specUpatedCells strategyUpdatedCells)

    errorMsgPred =
      "Simulator: Specification does not match the " ++
      "strategy as the following predicates differ:  " ++
      concatMap
        (\p -> predicateTermToString id p ++ " ")
        (toList $ difference specPredicates strategyPredicates)
   in
    case ( specUpatedCells `isSubsetOf` strategyUpdatedCells
         , specPredicates `isSubsetOf` strategyPredicates) of
      (True, True) -> Nothing
      (True, False) -> Just $ errorMsgPred
      (False, True) -> Just $ errorMsgCells
      (False, False) -> Just $ errorMsgCells ++ "\n" ++ errorMsgPred

  where
    assumptionsStr = fmap (fmap (stName $ symboltable spec)) . assumptions
    guaranteesStr = fmap (fmap (stName $ symboltable spec)) . guarantees

-----------------------------------------------------------------------------

-- | Get the simulation log

getLog
  :: SystemSimulation -> [(SystemOption, [(PredicateTerm String, Bool)])]

getLog =
  reverse . logTrace

-----------------------------------------------------------------------------
