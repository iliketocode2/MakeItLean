import Lake
open Lake DSL

/-! Ledger: a worked example of an app on the LeanKV substrate (spec package). -/
package ledger

require leankvImpl from "../kvstore/impl"
require makeitlean from "../../lean"

@[default_target]
lean_lib LedgerSpec where
  roots := #[`Ledger.Spec]
