import Lake
open Lake DSL

/-! AppName implementation: the function, its proof and the generated comparator solution. -/
package appnameImpl

require appname from ".."

@[default_target]
lean_lib AppNameImpl where
  roots := #[`AppNameImpl.Core, `AppNameImpl.Proofs]

/-- Generated comparator solution (`mil solution`). -/
@[default_target]
lean_lib AppNameSol where
  roots := #[`AppNameSol.Holes]
