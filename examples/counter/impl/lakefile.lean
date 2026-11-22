import Lake
open Lake DSL

/-! Counter implementation: the hole, its proof, the generated solution and the CLI. -/
package counterImpl

require counter from ".."

@[default_target]
lean_lib CounterImpl where
  roots := #[`CounterImpl.Core, `CounterImpl.Proofs]

/-- Generated comparator solution (`mil solution`). -/
@[default_target]
lean_lib CounterSol where
  roots := #[`CounterSol.Holes]

lean_exe counterCli where
  exeName := "counter"
  root := `CounterImpl.Shell
