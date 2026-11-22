import Lake
open Lake DSL

/-! Counter: a worked example of an app on the LeanKV substrate (spec package). -/
package counter

require leankvImpl from "../kvstore/impl"
require makeitlean from "../../lean"

@[default_target]
lean_lib CounterSpec where
  roots := #[`Counter.Spec]
