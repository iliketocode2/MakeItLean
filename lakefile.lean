import Lake
open Lake DSL

/-! The judge workspace (repository root). `lake comparator`'s sandbox only sees the directory of
the package it runs in, so the judge is the repository root and requires every app package from
its subdirectory. Comparator configs live in `judge/`. -/
package makeitleanJudge

require leankvImpl from "examples/kvstore/impl"
require counterImpl from "examples/counter/impl"
require ledgerImpl from "examples/ledger/impl"
