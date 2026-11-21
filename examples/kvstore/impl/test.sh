#!/usr/bin/env bash
# All implementation tests (Stages 3 and 5). Exits non-zero on any failure.
set -euo pipefail
cd "$(dirname "$0")"
TMP="${TMPDIR:-/tmp}/leankv-tests"; mkdir -p "$TMP"
lake build >/dev/null
lake build leankvCli leankvSelftest >/dev/null
echo "== Stage 3 differential tests (core vs spec, by evaluation)"
for t in IndexDiff LogDiff StoreDiff; do
  printf '%-10s ' "$t"; lake env lean "LeanKVImpl/Test/$t.lean" 2>&1 | tail -1
done
echo "== R23 fault harness + mutation gate (simulated FS, garbage crashes, bit flips)"
lake env lean LeanKVImpl/Test/Harness.lean 2>&1 | grep -A5 '^\[("core'
echo "== Real-file self-test (C leaf + core vs reference model)"
.lake/build/bin/leankv-selftest "$TMP/selftest" 40
echo "== Kill tests (real process, SIGKILL at random points)"
python3 -I tests/kill_test.py "$TMP/kill" 40
../tools/check_lock.sh
