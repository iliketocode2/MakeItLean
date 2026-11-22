import AppNameImpl.Proofs
import AppNameSol.Holes
import MakeItLean.Gates

/-! Stage 6: the verified-code audit (run by `mil audit`). The shell is trusted, not verified,
and must not be imported by verified modules. -/
#audit_verified AppNameImpl.Core AppNameImpl.Proofs AppNameSol forbid_imports AppNameImpl.Shell
