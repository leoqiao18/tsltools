-- |
-- Module      :  TSL.Simulation.FinitTraceChecker
-- Maintainer  :  Philippe Heim (Heim@ProjectJARVIS.de)
--
-- A simple finite trace checker
--
-----------------------------------------------------------------------------
{-# LANGUAGE ViewPatterns, LambdaCase, RecordWildCards #-}

-----------------------------------------------------------------------------
module TSL.Simulation.FiniteTraceChecker
  ( FiniteTrace
  , append
  , rewind
  , emptyTrace
  , violated
  , nextObligations
  ) where

-----------------------------------------------------------------------------
import TSL.Logic as Logic (Formula(..), PredicateTerm, SignalTerm)

import Control.Exception (assert)

import Data.Map as Map (Map, empty, insert, lookup, union)

-----------------------------------------------------------------------------
-- | A Finite Trace is a stack of updates and predicate evalutations 
-- (which are partial functions), a finite trace can be extended by append,
-- or rewind and the specification that should be fulfilled
--
data FiniteTrace c =
  FiniteTrace
    { trace :: [(c -> SignalTerm c, PredicateTerm c -> Bool)]
    , obligations :: [[(Formula c, Formula c)]]
    }

-----------------------------------------------------------------------------
-- | Adds an update and predicate evaluation at the end of a finite trace
append ::
     Ord c
  => FiniteTrace c
  -> (c -> SignalTerm c)
  -> (PredicateTerm c -> Bool)
  -> FiniteTrace c
append (ft@FiniteTrace {..}) updates predicates =
  let newTrace = (updates, predicates) : trace
      newOb =
        fmap
          (\(next, gar) -> (fst (checkNext newTrace empty next), gar))
          (nextObligations ft)
   in ft {trace = newTrace, obligations = newOb : obligations}

-----------------------------------------------------------------------------
-- | Reverts the last appending to the finite trace. If the trace is empty
-- the trace stays empty
rewind :: Ord c => FiniteTrace c -> FiniteTrace c
rewind ft@(FiniteTrace {..}) =
  case (trace, obligations) of
    ([], _) -> ft
    (_:tr, _:or) -> ft {trace = tr, obligations = or}
    _ -> assert False undefined

-----------------------------------------------------------------------------
-- | The empty finite trace
emptyTrace :: Ord c => ([Formula c], [Formula c]) -> FiniteTrace c
emptyTrace (assumptions, guarantees) =
  FiniteTrace
    { trace = []
    , obligations =
        [ fmap
            (\g -> (fst $ checkNext [] empty (Implies (And assumptions) g), g))
            guarantees
        ]
    }

-----------------------------------------------------------------------------
-- | This function returns the violated formulas
violated :: Eq c => FiniteTrace c -> [Formula c]
violated ft = fmap snd $ filter ((== FFalse) . fst) (nextObligations ft)

-----------------------------------------------------------------------------
-- | The next obligation of the trace
nextObligations :: FiniteTrace c -> [(Formula c, Formula c)]
nextObligations (FiniteTrace {..}) =
  case obligations of
    [] -> assert False undefined
    o:_ -> o

-----------------------------------------------------------------------------
-- | TODO
checkNext ::
     Ord c
  => [(c -> SignalTerm c, PredicateTerm c -> Bool)]
  -> Map (Formula c) (Formula c)
  -> Formula c
  -> (Formula c, Map (Formula c) (Formula c))
checkNext [] cache form =
  case form of
    Historically _ -> (TTrue, cache)
    Triggered _ _ -> (TTrue, cache)
    f -> (f, cache)
checkNext ts@(t:tr) cache form =
  let simpForm = simplify form
   in case Map.lookup simpForm cache of
        Just f -> (f, cache)
        Nothing ->
          let (nextForm, cache') =
                case form of
                  TTrue -> (TTrue, empty)
                  FFalse -> (FFalse, empty)
                  Check p ->
                    if (snd t) p
                      then (TTrue, empty)
                      else (FFalse, empty)
                  Update c st ->
                    if (fst t) c == st
                      then (TTrue, empty)
                      else (FFalse, empty)
                  Not f ->
                    let (f', c) = checkNext ts cache f
                     in (Not f', c)
                  And fs ->
                    let (fs', c) =
                          foldl
                            (\(fr, c) e ->
                               let (f', c') = checkNext ts c e
                                in (f' : fr, c'))
                            ([], cache)
                            (reverse fs)
                     in (And fs', c)
                  Or fs ->
                    let (fs', c) =
                          foldl
                            (\(fr, c) e ->
                               let (f', c') = checkNext ts c e
                                in (f' : fr, c'))
                            ([], cache)
                            (reverse fs)
                     in (Or fs', c)
                  Next f -> (f, cache)
                  Previous f ->
                    case tr of
                      [] -> (FFalse, empty)
                      _ -> checkNext ts cache $ fst $ checkNext tr empty f
                  Historically f ->
                    checkNext ts cache $
                    And [f, fst $ checkNext tr empty (Historically f)]
                  Triggered f1 f2 ->
                    checkNext ts cache $
                    And
                      [f2, Or [f1, fst $ checkNext tr empty (Triggered f1 f2)]]
                  -- Expanded
                  Implies f1 f2 -> checkNext ts cache $ Or [Not f1, f2]
                  Equiv f1 f2 ->
                    checkNext ts cache $ And [Implies f1 f2, Implies f2 f1]
                  Globally f -> checkNext ts cache $ And [f, Next (Globally f)]
                  Finally f -> checkNext ts cache $ Or [f, Next (Finally f)]
                  Until f1 f2 ->
                    checkNext ts cache $ Or [f2, And [f1, Next (Until f1 f2)]]
                  Weak f1 f2 ->
                    checkNext ts cache $ Or [f2, And [f1, Next (Until f1 f2)]]
                  Release f1 f2 -> checkNext ts cache $ Weak f2 (And [f1, f2])
                  Once f -> checkNext ts cache $ Or [f, Previous (Once f)]
                  Since f1 f2 ->
                    checkNext ts cache $
                    Or [f2, And [f1, Previous (Since f1 f2)]]
           in ( (simplify nextForm)
              , insert simpForm (simplify nextForm) (union cache cache'))

-----------------------------------------------------------------------------
-- | Simplifies a TSL formula
simplify :: Eq c => Formula c -> Formula c
simplify =
  \case
    Not f ->
      case simplify f of
        TTrue -> FFalse
        FFalse -> TTrue
        f' -> Not f'
    And [] -> TTrue
    And [f] -> simplify f
    Or [f] -> simplify f
    And fs ->
      let fs' = map simplify fs
       in if exists isFalse fs'
            then FFalse
            else And $
                 removeDoubles $
                 foldl
                   (\xs e ->
                      case e of
                        And g -> g ++ xs
                        TTrue -> xs
                        g -> g : xs)
                   []
                   fs'
    Or [] -> FFalse
    Or fs ->
      let fs' = map simplify fs
       in if exists isTrue fs'
            then TTrue
            else Or $
                 removeDoubles $
                 foldl
                   (\xs e ->
                      case e of
                        Or g -> g ++ xs
                        FFalse -> xs
                        g -> g : xs)
                   []
                   fs'
    Implies f1 f2 ->
      case (simplify f1, simplify f2) of
        (FFalse, _) -> TTrue
        (TTrue, f) -> f
        (f1', f2') -> Implies f1' f2'
    Equiv f1 f2 ->
      case (simplify f1, simplify f2) of
        (FFalse, f) -> simplify (Not f)
        (f, FFalse) -> simplify (Not f)
        (f, TTrue) -> f
        (TTrue, f) -> f
        (f1', f2') -> Equiv f1' f2'
    f -> f
  where
    isFalse FFalse = True
    isFalse _ = False
    --
    isTrue TTrue = True
    isTrue _ = False
    --
    exists p xs = not (all (\z -> not (p z)) xs)
    -- 
    removeDoubles :: Eq a => [a] -> [a]
    removeDoubles [] = []
    removeDoubles (x:xr) =
      if x `elem` xr
        then removeDoubles xr
        else x : removeDoubles xr
