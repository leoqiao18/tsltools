----------------------------------------------------------------------------
-- |
-- Module      :  Main
-- Maintainer  :  Wonhyuk Choi
--
-- Underapproximates a Temporal Stream Logic Modulo Theories specification
-- into a Temporal Stream Logic specification so that it can be synthesized.
-- Procedure is based on the paper
-- "Can Reactive Synthesis and Syntax-Guided Synthesis Be Friends?"
--
-----------------------------------------------------------------------------
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE NamedFieldPuns #-}
-----------------------------------------------------------------------------

module Main
  ( main
  ) where

-----------------------------------------------------------------------------

import Config (Configuration(..), Flag(..), parseArguments)

import EncodingUtils (initEncoding)

import FileUtils (writeContent, loadTSLMT)

import TSL ( Specification(..)
           , SymbolTable(..)
           , SolverErr(..)
           , fromSpec
           , getPredicateLiterals
           , consistencyChecking
           , checkSat
           )

import System.Exit(die)

-----------------------------------------------------------------------------

writeOutput :: Maybe FilePath -> Either String String -> IO ()
writeOutput _ (Left errMsg)      = die errMsg
writeOutput path (Right content) = writeContent path $ removeDQuote content
  where removeDQuote = filter (/= '\"')

-- consistencyAssumptions :: Theory -> Specification -> Either SolverErr [String]
-- consistencyAssumptions theory spec = assumptions
--   where
--     predLits    = getPredicateLiterals spec
--     assumptions = consistencyChecking theory predLits checkSat

main :: IO ()
main = do
  initEncoding
  Configuration{input, output, flag} <- parseArguments

  (theory, spec) <- loadTSLMT input
  
  let unhash  = stName $ symboltable spec
      content = case flag of
        (Just Predicates)  -> Right $ unlines $ map (show . (fmap unhash)) $ getPredicateLiterals spec
        (Just Grammar)     -> Right $ show $ fromSpec spec
        (Just Consistency) -> Right $ show theory
        (Just flag')       -> Left $ "Unimplemented flag: " ++ show flag'
        Nothing            -> Left $ "tslmt2tsl end-to-end not yet supported"

  writeOutput output content
