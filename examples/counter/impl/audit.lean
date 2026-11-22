import CounterImpl.Proofs
import CounterSol.Holes
import MakeItLean.Gates

/-! Stage 6: the verified-code audit (run by `mil audit`). The shell is trusted, not verified,
and must not be imported by verified modules. -/
#audit_verified CounterImpl.Core CounterImpl.Proofs CounterSol forbid_imports CounterImpl.Shell
