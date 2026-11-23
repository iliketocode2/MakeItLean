import Lake
open Lake DSL

/-! Ledger implementation: the hole, its proof, the generated solution and the CLI. -/
package ledgerImpl

require ledger from ".."

@[default_target]
lean_lib LedgerImpl where
  roots := #[`LedgerImpl.Core, `LedgerImpl.Proofs, `LedgerImpl.Text]

/-- Generated comparator solution (`mil solution`). -/
@[default_target]
lean_lib LedgerSol where
  roots := #[`LedgerSol.Holes]

lean_exe ledgerCli where
  exeName := "ledger"
  root := `LedgerImpl.Shell

/-- The reference model as a process: the test oracle for differential tests (R19). -/
lean_exe ledgerOracle where
  exeName := "ledger-oracle"
  root := `LedgerImpl.Oracle
