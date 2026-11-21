#!/usr/bin/env bash
# Stage 6 audit: the CI gate. Every step must pass. Run from anywhere.
set -euo pipefail
KV="$(cd "$(dirname "$0")/.." && pwd)"
ROOT="$(cd "$KV/../.." && pwd)"
step() { printf '\n== %s\n' "$1"; }
step "1. Frozen spec unchanged (spec.lock)";            "$KV/tools/check_lock.sh"
step "2. Spec builds: English-doc gate, hole gate, worked examples"
( cd "$KV" && lake build LeanKVSpec 2>&1 | grep -E 'gate|error' )
step "3. Spec axioms: only the 9 obligations open"
( cd "$KV" && lake env lean tools/SpecAxioms.lean 2>&1 | tail -1 )
step "4. Comparator (sandboxed, --paranoid external kernels) judges all obligations"
( cd "$KV/impl" && PARANOID=1 tools/judge.sh | tail -1 )
step "5. Verified-module audit: axioms, no sorry/unsafe/partial/opaque/implemented_by/extern"
( cd "$KV/impl" && lake env lean audit/AuditVerified.lean 2>&1 | tail -1 )
step "6. Tests: differential, R23 harness + mutation gate, real-file self-test, kill tests"
( cd "$KV/impl" && ./test.sh )
step "7. Anti-cheating regression (comparator smoke test)"
"$ROOT/tests/comparator-smoke/run.sh"
printf '\nAUDIT PASSED\n'
