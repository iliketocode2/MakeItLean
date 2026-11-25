import Lake
open Lake DSL

/-! AppName: a library of related functions (spec package). No storage substrate and no shell:
reference implementations, properties relating them, and one obligation per function. -/
package appname

require makeitlean from "MIL_ROOT/lean"

@[default_target]
lean_lib AppNameSpec where
  roots := #[`AppName.Spec]
