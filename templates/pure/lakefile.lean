import Lake
open Lake DSL

/-! AppName: a pure-function app (spec package). No storage substrate and no shell: one function,
its precondition and postcondition, proven by the implementation. -/
package appname

require makeitlean from "MIL_ROOT/lean"

@[default_target]
lean_lib AppNameSpec where
  roots := #[`AppName.Spec]
