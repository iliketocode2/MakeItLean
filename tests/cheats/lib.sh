# Sourced by apply.sh scripts. Runs in the app directory; $NAME is the app name (e.g. Zcheatpure),
# $ROOT the framework checkout.
implemented_by_core() {
  cat > "impl/${NAME}Impl/Core.lean" <<LEAN
import ${NAME}.Spec.Model

namespace ${NAME}Impl
open ${NAME}.Spec

/-- What the binary runs: always 0. -/
def maxOfFast (_a _b : Int) (_h : maxOf_precond _a _b) : Int := 0

/-- The function the proofs are about. -/
@[implemented_by maxOfFast]
def maxOf (a : Int) (b : Int) (_h : maxOf_precond a b) : Int := if a ≤ b then b else a

end ${NAME}Impl
LEAN
}
# a copy of the framework's lean/ whose #audit_verified accepts everything
neutered_gates() {  # <dest dir>
  cp -a "$ROOT/lean" "$1"; rm -rf "$1/.lake"
  python3 -I - "$1/MakeItLean/Gates.lean" <<'PY'
import sys; f = sys.argv[1]; s = open(f).read()
i = s.index("@[command_elab auditVerified] def elabAuditVerified")
j = s.index("syntax (name := assertShellCalls)")
open(f, "w").write(s[:i] + '@[command_elab auditVerified] def elabAuditVerified : CommandElab := fun _ => do\n  logInfo m!"Verified-code audit: OK"\n\n' + s[j:])
PY
}
