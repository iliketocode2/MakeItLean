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

step "0. Every lakefile require names a tracked path (else a fresh clone does not build)"
check 'check_requires:' python3 -I "$ROOT/tools/check_requires.py"

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
  # serve_test.sh expects both binaries already built (a fresh CI checkout has neither)
  check 'Build completed' bash -c "cd '$ROOT/examples/ledger/impl' && lake build ledgerCli ledgerOracle"
  check 'passed|consistent|agree|reach|replay' "$ROOT/examples/ledger/impl/tests/serve_test.sh"
  if ! node -e 'process.exit(+process.versions.node.split(".")[0] >= 24 ? 0 : 1)' 2>/dev/null; then
    echo "FAILED: the HTTP tests need Node.js 24 or later on PATH"; exit 1
  fi
  check 'V8:|agree|planted_bug: [0-9]|replay:|edge_test:|kill_test:|all passed' "$ROOT/examples/ledger/http/test.sh"

  step "8. A fresh app from the template: init, judge, tests, freeze, strict audit"
  APP="$ROOT/examples/ztemplatecheck"
  PAPP="$ROOT/bench/ztemplatecheck/zpurecheck"   # deeper than examples/: exercises MIL_ROOT
  EXT="$(mktemp -d -t mil-ext-XXXXXX)"   # step 9: apps outside the checkout
  UPG="$ROOT/examples/zupgrade"          # step 8e: an app moved forward by `mil upgrade`
  restore() { rm -rf "$APP" "$ROOT/bench/ztemplatecheck" "$EXT" "$UPG"; }
  trap restore EXIT
  check 'created' bash -c "cd '$ROOT' && '$MIL' init Ztemplatecheck examples/ztemplatecheck"
  check 'ACCEPTED' "$MIL" judge "$APP/mil.json"
  check 'passed|consistent|agree' "$APP/impl/test.sh"
  check 'Frozen' "$MIL" freeze "$APP/mil.json" ci-template-check
  check 'AUDIT' "$MIL" audit "$APP/mil.json"

  step "8b. A fresh pure-function app (mil init --pure): init, judge, freeze, strict audit"
  check 'created' bash -c "cd '$ROOT' && '$MIL' init --pure Zpurecheck bench/ztemplatecheck/zpurecheck"
  check 'ACCEPTED' "$MIL" judge "$PAPP/mil.json"
  check 'Frozen' "$MIL" freeze "$PAPP/mil.json" ci-template-check
  check 'Trust gate|AUDIT' "$MIL" audit "$PAPP/mil.json"

  step "8c. Staged judge: a planted sorry is REJECTED; two apps judged in parallel; no root workspace"
  python3 -I - "$PAPP/impl/fill.json" <<'PY'
import json, sys; f = sys.argv[1]; j = json.load(open(f))
j["obligations"] = {k: "sorry" for k in j["obligations"]}; json.dump(j, open(f, "w"))
PY
  if "$MIL" judge "$PAPP/mil.json" >/tmp/mil-neg.$$ 2>&1; then echo "FAILED: planted sorry was accepted"; exit 1; fi
  grep -q 'REJECTED' /tmp/mil-neg.$$ && grep -q 'sorryAx' /tmp/mil-neg.$$ \
    || { echo "FAILED: planted sorry not rejected by the comparator"; tail -20 /tmp/mil-neg.$$; exit 1; }
  rm -f /tmp/mil-neg.$$; echo "planted sorry: REJECTED (sorryAx)"
  "$MIL" judge "$ROOT/examples/counter/mil.json" >/tmp/mil-par1.$$ 2>&1 & p1=$!
  "$MIL" judge "$ROOT/examples/ledger/mil.json" >/tmp/mil-par2.$$ 2>&1 & p2=$!
  wait $p1 && wait $p2 && grep -q ACCEPTED /tmp/mil-par1.$$ && grep -q ACCEPTED /tmp/mil-par2.$$ \
    || { echo "FAILED: parallel judge"; tail -20 /tmp/mil-par1.$$ /tmp/mil-par2.$$; exit 1; }
  rm -f /tmp/mil-par1.$$ /tmp/mil-par2.$$; echo "parallel judge (Counter, Ledger): both ACCEPTED"
  for f in lakefile.lean lake-manifest.json judge; do
    [ ! -e "$ROOT/$f" ] || { echo "FAILED: $f appeared at the repository root"; exit 1; }
  done
  echo "no root judge workspace: ok"
  # lock coverage: drop a frozen file's line from spec.lock, then edit that file
  M="Zpurecheck/Spec/Model.lean"
  grep -v " $M\$" "$PAPP/spec.lock" > "$PAPP/spec.lock.tmp" && mv "$PAPP/spec.lock.tmp" "$PAPP/spec.lock"
  echo "-- tampered" >> "$PAPP/$M"
  if "$MIL" check-lock "$PAPP/mil.json" >/tmp/mil-lock.$$ 2>&1; then echo "FAILED: a line dropped from spec.lock went unnoticed"; exit 1; fi
  grep -q 'does not cover exactly' /tmp/mil-lock.$$ || { echo "FAILED: wrong lock error"; cat /tmp/mil-lock.$$; exit 1; }
  rm -f /tmp/mil-lock.$$; echo "lock coverage: a dropped spec.lock line is a MISMATCH"

  step "8d. The cheat suite: every known way to a false AUDIT PASSED is rejected (Phase 6 W0)"
  check 'control:|cheat rejected|cheats:' "$ROOT/tests/cheats/run.sh"

  step "8e. Usable by others: --lib template, versions, mil upgrade, mil check, mil doctor (Phase 6 W-U)"
  LAPP="$ROOT/bench/ztemplatecheck/zlibcheck"
  check 'created' bash -c "cd '$ROOT' && '$MIL' init --lib Zlibcheck bench/ztemplatecheck/zlibcheck"
  check 'CHECK PASSED' "$MIL" check "$LAPP/mil.json"
  check 'ACCEPTED' "$MIL" judge "$LAPP/mil.json"
  check 'Frozen' "$MIL" freeze "$LAPP/mil.json" ci-template-check
  check 'AUDIT' "$MIL" audit "$LAPP/mil.json"
  # versions: an app for a newer framework, and one for an unsupported older one, are refused
  VAPP="$ROOT/bench/ztemplatecheck/zvercheck"; cp -a "$LAPP" "$VAPP"; rm -f "$VAPP/spec.lock"
  setver() { python3 -I -c "import json,sys; f=sys.argv[1]; j=json.load(open(f)); j['framework_version']=sys.argv[2]; json.dump(j,open(f,'w'),indent=2)" "$VAPP/mil.json" "$1"; }
  setver 99.0.0
  if "$MIL" judge "$VAPP/mil.json" >/tmp/mil-ver.$$ 2>&1 || ! grep -q 'update the framework checkout' /tmp/mil-ver.$$; then echo "FAILED: an app for a newer framework was not refused"; cat /tmp/mil-ver.$$; exit 1; fi
  setver 0.0.1
  if "$MIL" judge "$VAPP/mil.json" >/tmp/mil-ver.$$ 2>&1 || ! grep -q 'mil upgrade' /tmp/mil-ver.$$; then echo "FAILED: an app for an unsupported framework was not refused"; cat /tmp/mil-ver.$$; exit 1; fi
  rm -f /tmp/mil-ver.$$; echo "versions: newer and unsupported framework versions refused"
  # mil check catches the W0 cheat (compiled code differs from the proven body)
  setver "$(cat "$ROOT/VERSION")"
  python3 -I - "$VAPP/impl/ZlibcheckImpl/Core.lean" <<'PY2'
import sys; f = sys.argv[1]; s = open(f).read()
o = "def size (s : NatSet) : Nat := s.length"
assert o in s
open(f, "w").write(s.replace(o, "def sizeFast (_s : NatSet) : Nat := 0\n\n@[implemented_by sizeFast]\n" + o))
PY2
  if "$MIL" check "$VAPP/mil.json" >/tmp/mil-chk.$$ 2>&1 || ! grep -q 'implemented_by: ZlibcheckImpl.size' /tmp/mil-chk.$$; then echo "FAILED: mil check missed an implemented_by cheat"; tail -20 /tmp/mil-chk.$$; exit 1; fi
  rm -f /tmp/mil-chk.$$; echo "mil check: implemented_by cheat rejected"
  # mil upgrade: Counter as it was before W0 (no framework_version, audit or selftest sections; its
  # own impl/audit.lean) is moved forward, and gets exactly Counter's sections
  legacy() {
    rm -rf "$UPG"; cp -a "$ROOT/examples/counter" "$UPG"; rm -rf "$UPG/impl/.mil"
    python3 -I -c "import json,sys; f=sys.argv[1]; j=json.load(open(f)); [j.pop(k) for k in ('framework_version','audit','selftest')]; json.dump(j,open(f,'w'),indent=2)" "$UPG/mil.json"
    git -C "$ROOT" show 79d2de9:examples/counter/impl/audit.lean > "$UPG/impl/audit.lean"
  }
  legacy
  check 'Dry run' "$MIL" upgrade "$UPG/mil.json"
  check 'Applied' "$MIL" upgrade --apply "$UPG/mil.json"
  python3 -I - "$UPG/mil.json" "$ROOT/examples/counter/mil.json" <<'PY2'
import json, sys; a, b = (json.load(open(p)) for p in sys.argv[1:])
bad = [k for k in ("framework_version", "audit", "selftest") if a.get(k) != b.get(k)]
if bad: print(f"FAILED: mil upgrade derived different {bad}"); sys.exit(1)
print("mil upgrade: derived sections equal Counter's")
PY2
  check 'CHECK PASSED' "$MIL" check "$UPG/mil.json"
  legacy
  check 'Frozen' "$MIL" freeze "$UPG/mil.json" ci-legacy
  check 'Applied' "$MIL" upgrade --apply "$UPG/mil.json"
  [ -f "$UPG/spec.lock.v1" ] && [ ! -e "$UPG/spec.lock" ] || { echo "FAILED: mil upgrade did not keep the old lock as spec.lock.v1"; exit 1; }
  echo "mil upgrade: the old lock kept as spec.lock.v1; a new sign-off is needed"
  check 'doctor:' "$MIL" doctor

  step "9. Apps outside the checkout: framework by pinned git require (this checkout's HEAD)"
  # Only committed framework code reaches these apps (they clone HEAD): CI tests exactly the commit.
  # Lake fetches with --filter=tree:0, which hangs against a shallow repository: fail fast instead.
  if [ "$(git -C "$ROOT" rev-parse --is-shallow-repository)" = true ]; then
    echo "FAILED: $ROOT is a shallow clone; step 9 needs full history (git fetch --unshallow, or fetch-depth: 0 in CI)"; exit 1
  fi
  export MIL_GIT_URL="$ROOT" MIL_GIT_REV="$(git -C "$ROOT" rev-parse HEAD)"
  check 'created|wrote' bash -c "cd '$EXT' && '$MIL' init --agent claude Zextapp zextapp"
  grep -q "from git \"$ROOT\" @ \"$MIL_GIT_REV\"" "$EXT/zextapp/lakefile.lean" || { echo "FAILED: no pinned git require"; exit 1; }
  python3 -I -m json.tool "$EXT/zextapp/.claude/settings.json" >/dev/null || { echo "FAILED: settings.json"; exit 1; }
  check 'Build completed' bash -c "cd '$EXT/zextapp' && lake build"
  check 'ACCEPTED' "$MIL" judge "$EXT/zextapp/mil.json"
  check 'passed|consistent|agree' "$EXT/zextapp/impl/test.sh"
  check 'wrote SPEC_REVIEW' "$MIL" review "$EXT/zextapp/mil.json"
  [ -s "$EXT/zextapp/SPEC_REVIEW.md" ] || { echo "FAILED: mil review wrote no SPEC_REVIEW.md"; exit 1; }
  check 'Frozen' "$MIL" freeze "$EXT/zextapp/mil.json" ci-external-check
  check 'AUDIT' "$MIL" audit "$EXT/zextapp/mil.json"
  check 'created|wrote' bash -c "cd '$EXT' && '$MIL' init --pure --agent codex Zextpure zextpure"
  check 'ACCEPTED' "$MIL" judge "$EXT/zextpure/mil.json"
  check 'Frozen' "$MIL" freeze "$EXT/zextpure/mil.json" ci-external-check
  check 'AUDIT' "$MIL" audit "$EXT/zextpure/mil.json"
  unset MIL_GIT_URL MIL_GIT_REV
fi

printf '\nALL CHECKS PASSED\n'
