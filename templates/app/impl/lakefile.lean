import Lake
open Lake DSL

/-! AppName implementation: the hole, its proof, the generated solution and the CLI. -/
package appnameImpl

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
