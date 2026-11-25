import Lake
open Lake DSL

/-! AppName implementation: the hole, its proof, the generated solution and the CLI. -/
package appnameImpl where
  -- share the spec package's dependency clones, so a git-fetched framework is cloned and
  -- built once (two workspaces with separate clones disagree on which one holds the build)
  packagesDir := "../.lake/packages"

require appname from ".."

@[default_target]
lean_lib AppNameImpl where
  roots := #[`AppNameImpl.Core, `AppNameImpl.Proofs, `AppNameImpl.Text]

/-- Generated comparator solution (`mil solution`). -/
@[default_target]
lean_lib AppNameSol where
  roots := #[`AppNameSol.Holes]

lean_exe appnameCli where
  exeName := "appname"
  root := `AppNameImpl.Shell

/-- The reference model as a process: the test oracle for differential tests. -/
lean_exe appnameOracle where
  exeName := "appname-oracle"
  root := `AppNameImpl.Oracle
