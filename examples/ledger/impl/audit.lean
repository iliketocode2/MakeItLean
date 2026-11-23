import LedgerImpl.Proofs
import LedgerSol.Holes
import MakeItLean.Gates

/-! Stage 6: the verified-code audit (run by `mil audit`). The shell is trusted, not verified,
and must not be imported by verified modules. -/
#audit_verified LedgerImpl.Core LedgerImpl.Proofs LedgerSol forbid_imports LedgerImpl.Shell
