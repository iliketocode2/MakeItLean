#!/usr/bin/env bash
# Stage 3 differential tests: the core against the frozen spec (each prints its tallies).
set -euo pipefail
cd "$(dirname "$0")"
lake build >/dev/null
for t in IndexDiff LogDiff StoreDiff; do
  printf '%-10s ' "$t"; lake env lean "LeanKVImpl/Test/$t.lean" 2>&1 | tail -1
done
../tools/check_lock.sh
