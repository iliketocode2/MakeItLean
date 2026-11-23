import AppNameImpl.Proofs
import AppNameSol.Holes
import MakeItLean.Gates

/-! Stage 6: the verified-code audit (run by `mil audit`). A pure app has no shell; the forbidden
module is a placeholder that keeps the check's shape. -/
#audit_verified AppNameImpl.Core AppNameImpl.Proofs AppNameSol forbid_imports AppNameImpl.Shell
