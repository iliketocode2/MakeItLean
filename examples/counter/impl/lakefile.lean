import Lake
open Lake DSL

/-! Counter implementation: the hole, its proof, the generated solution and the CLI. -/
package counterImpl

require counter from ".."

@[default_target]
lean_lib CounterImpl where
  roots := #[`CounterImpl.Core, `CounterImpl.Proofs, `CounterImpl.Text]

/-- Generated comparator solution (`mil solution`). -/
@[default_target]
lean_lib CounterSol where
  roots := #[`CounterSol.Holes]

lean_exe counterCli where
  exeName := "counter"
  root := `CounterImpl.Shell

/-- The reference model as a process: the test oracle for differential tests. -/
lean_exe counterOracle where
  exeName := "counter-oracle"
  root := `CounterImpl.Oracle
