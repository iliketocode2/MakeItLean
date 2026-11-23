#!/usr/bin/env bash
# Every MakeItLean check, in one command (also what CI runs). Exits non-zero on the first failure.
#
#   tests/all.sh            everything
#   tests/all.sh --quick    skip the fresh-template run and the real-file tests
#
# Order: the framework's own gates first (if they are broken, no app result means anything),
# then the anti-cheating regression, then each app's full audit and real-file tests.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
QUICK=0; [ "${1:-}" = "--quick" ] && QUICK=1
MIL="$ROOT/cli/.lake/build/bin/mil"
step() { printf '\n===== %s\n' "$1"; }
# check <pattern> <command…>: run once; on success show the lines matching <pattern>, on failure
# show the end of the log and stop.
check() {
  local pat="$1"; shift
  local log; log="$(mktemp)"
  if "$@" >"$log" 2>&1; then grep -E "$pat" "$log" || true; rm -f "$log"
  else echo "FAILED: $*"; tail -40 "$log"; rm -f "$log"; exit 1; fi
}

step "1. Framework gates and their negative tests (lean/)"
check 'Build completed' bash -c "cd '$ROOT/lean' && lake build"

step "1b. Guard hooks: frozen files and agent roles (main checkout and a worktree)"
check 'test_guards:' python3 -I "$ROOT/tools/hooks/test_guards.py"

step "2. Build the mil CLI"
check 'Build completed' bash -c "cd '$ROOT/cli' && lake build"

step "3. Anti-cheating regression: the comparator accepts the honest solution, rejects 4 cheats"
"$ROOT/tests/comparator-smoke/run.sh"

step "4. LeanKV (the substrate): lock, spec gates, comparator --paranoid, audit, tests"
check '^== |PASSED|ACCEPTED' "$ROOT/examples/kvstore/tools/audit.sh"

step "5. Ledger (frozen ledger-v1): mil audit"
check 'spec.lock|gate:|ACCEPTED|audit:|AUDIT' "$MIL" audit "$ROOT/examples/ledger/mil.json"

step "6. Counter (worked example, not user-signed): mil audit --allow-unfrozen"
check 'gate:|ACCEPTED|audit:|AUDIT' "$MIL" audit --allow-unfrozen "$ROOT/examples/counter/mil.json"

if [ $QUICK -eq 0 ]; then
  step "7. Real-file tests (CLI, limits, kill tests)"
  check 'passed|consistent|agree' "$ROOT/examples/ledger/impl/test.sh"
  check 'passed|consistent|agree' "$ROOT/examples/counter/impl/test.sh"

  step "7b. Ledger serve mode and HTTP API against the model (Phase 3: V1-V6, V8)"
  check 'passed|consistent|agree|reach|replay' "$ROOT/examples/ledger/impl/tests/serve_test.sh"
  if ! node -e 'process.exit(+process.versions.node.split(".")[0] >= 24 ? 0 : 1)' 2>/dev/null; then
    echo "FAILED: the HTTP tests need Node.js 24 or later on PATH"; exit 1
  fi
  check 'V8:|agree|planted_bug: [0-9]|replay:|edge_test:|kill_test:|all passed' "$ROOT/examples/ledger/http/test.sh"

  step "8. A fresh app from the template: init, judge, tests, freeze, strict audit"
  APP="$ROOT/examples/ztemplatecheck"
  cp "$ROOT/lakefile.lean" "$ROOT/.lakefile.lean.bak"; cp "$ROOT/lake-manifest.json" "$ROOT/.lake-manifest.json.bak"
  restore() {
    rm -rf "$APP" "$ROOT/judge/Ztemplatecheck_Spec.json"
    mv "$ROOT/.lakefile.lean.bak" "$ROOT/lakefile.lean"; mv "$ROOT/.lake-manifest.json.bak" "$ROOT/lake-manifest.json"
  }
  trap restore EXIT
  check 'created' bash -c "cd '$ROOT' && '$MIL' init Ztemplatecheck examples/ztemplatecheck"
  check 'ACCEPTED' "$MIL" judge "$APP/mil.json"
  check 'passed|consistent|agree' "$APP/impl/test.sh"
  check 'Frozen' "$MIL" freeze "$APP/mil.json" ci-template-check
  check 'AUDIT' "$MIL" audit "$APP/mil.json"
fi

printf '\nALL CHECKS PASSED\n'
