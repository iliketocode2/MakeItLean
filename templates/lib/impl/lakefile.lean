import Lake
open Lake DSL

/-! AppName implementation: the functions, their proofs and the generated comparator solution. -/
package appnameImpl where
  -- share the spec package's dependency clones, so a git-fetched framework is cloned and
  -- built once (two workspaces with separate clones disagree on which one holds the build)
  packagesDir := "../.lake/packages"

require appname from ".."

@[default_target]
lean_lib AppNameImpl where
  roots := #[`AppNameImpl.Core, `AppNameImpl.Proofs]

/-- Generated comparator solution (`mil solution`). Not a default target: it exists only after
`mil judge` generates it, so a plain `lake build` works during Stage 3. -/
lean_lib AppNameSol where
  roots := #[`AppNameSol.Holes]
