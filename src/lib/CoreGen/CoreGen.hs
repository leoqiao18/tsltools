-----------------------------------------------------------------------------
-- |
-- Module      :  CoreGen.CoreGen
-- Maintainer  :  Philippe Heim (Heim@ProjectJARVIS.de)
--
-- Generates and unsat / unrealizabilty core
--
-----------------------------------------------------------------------------
{-# LANGUAGE ViewPatterns, LambdaCase, RecordWildCards #-}

-- TODO
-- - fix to right core gen
-----------------------------------------------------------------------------
module CoreGen.CoreGen
  ( Query(..)
  , getCores
  , genQuery
  ) where

-----------------------------------------------------------------------------
import Data.Set
import TSL.Specification (TSLSpecification(..), tslSpecToSpec)
import TSL.TLSF (toTLSF)
import TSL.ToString (tslSpecToString)

-----------------------------------------------------------------------------
--
-- This represents some query to check.
-- - synthSpec: String passed to the SAT/Synthesis - Tool
-- - potCore: Core in case of unsat/unrez
--
data Query =
  Query
    { potCore :: TSLSpecification
    , synthSpec :: String
    }

-----------------------------------------------------------------------------
--
-- Given some TSL Specification generates a query to check if this specification
-- is a core
--
genQuery :: TSLSpecification -> Query
genQuery spec =
  Query {potCore = spec, synthSpec = toTLSF "CoreCandidat" (tslSpecToSpec spec)}

-----------------------------------------------------------------------------
--
-- Given a TSL Specification generates a list of queries to find the core
--
getCores :: TSLSpecification -> [Query]
getCores tsl@TSLSpecification {guarantees = g} =
  fmap
    (\indices -> genQuery $ tsl {guarantees = choose indices})
    (sortedPowerSet $ length g)
  where
    choose indices =
      fmap snd $ Prelude.filter (\(a, _) -> member a indices) $ zip [0 ..] g

-----------------------------------------------------------------------------
--
-- Computes the powerset (in list form) sorted by by length of the set
-- Note that this is not done by powerset and then sort to do it on the fly
--
sortedPowerSet :: Int -> [Set Int]
sortedPowerSet n = powerSetB n n
  where
    powerSetB :: Int -> Int -> [Set Int]
    powerSetB n bound
      | n < 1 = []
      | n == 1 = [fromList [i] | i <- [0 .. bound - 1]]
      | otherwise =
        let sub = powerSetB (n - 1) bound
            subNew =
              concatMap
                (\s -> [insert i s | i <- [0 .. bound - 1], notMember i s])
                (Prelude.filter (\s -> size s == n - 1) sub)
            new = toList (fromList subNew)
         in sub ++ new
