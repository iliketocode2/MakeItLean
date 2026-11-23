import Lake
open Lake DSL

/-! The judge workspace (repository root). `lake comparator`'s sandbox only sees the directory of
the package it runs in, so the judge is the repository root and requires every app package from
its subdirectory. Comparator configs live in `judge/`. -/
package makeitleanJudge

require leankvImpl from "examples/kvstore/impl"
require counterImpl from "examples/counter/impl"
require ledgerImpl from "examples/ledger/impl"
require verinaAdvanced12Impl from "bench/verina/runs/a2/framework/verina_advanced_12/impl"
require verinaAdvanced15Impl from "bench/verina/runs/a2/framework/verina_advanced_15/impl"
require verinaBasic101Impl from "bench/verina/runs/a2/framework/verina_basic_101/impl"
require verinaBasic108Impl from "bench/verina/runs/a2/framework/verina_basic_108/impl"
require verinaBasic12Impl from "bench/verina/runs/a2/framework/verina_basic_12/impl"
