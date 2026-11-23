import Lake
open Lake DSL

/-! AppName implementation: the function, its proof and the generated comparator solution. -/
package appnameImpl

require appname from ".."

@[default_target]
lean_lib AppNameImpl where
  roots := #[`AppNameImpl.Core, `AppNameImpl.Proofs]

/-- Generated comparator solution (`mil solution`). Not a default target: it exists only after
`mil judge` generates it, so a plain `lake build` works during Stage 3. -/
lean_lib AppNameSol where
  roots := #[`AppNameSol.Holes]
