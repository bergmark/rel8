{-# language FlexibleContexts #-}

module Rel8.Query.Evaluate
  ( eval
  )
where

-- base
import Prelude ()

-- rel8
import Rel8.Expr ( Expr )
import Rel8.Query ( Query )
import Rel8.Query.Values ( values )
import Rel8.Table ( Table )


-- | 'eval' takes expressions that could potentially have side effects and
-- \"runs\" them in the 'Query' monad. The returned expressions have no
-- side effetcs and can safely be reused.
eval :: Table Expr a => a -> Query a
eval a = values [a]
