#!/usr/bin/env bash
# Stage 4/6 verdict: check the frozen spec's lock, regenerate the solution, build, and let
# `lake comparator` (sandboxed; --paranoid with PARANOID=1) judge all obligations against the
# frozen spec. Runs from the repository-root judge workspace, whose sandbox sees every package.
# Exit 0 = accepted.
set -euo pipefail
IMPL="$(cd "$(dirname "$0")/.." && pwd)"
ROOT="$(cd "$IMPL/../../.." && pwd)"
"$IMPL/../tools/check_lock.sh" >/dev/null
( cd "$IMPL" && python3 tools/make_solution.py >/dev/null && lake build >/dev/null )
cd "$ROOT"
python3 - <<'PY'
import json; c = json.load(open("examples/kvstore/comparator.json")); c["solution_module"] = "LeanKVSol.Holes"
json.dump(c, open("judge/leankv.json", "w"), indent=1)
PY
lake build LeanKV.Spec LeanKVSol.Holes >/dev/null
lake comparator --config=judge/leankv.json ${PARANOID:+--paranoid} >/dev/null 2>&1 \
  && echo "ACCEPTED: all obligations proven against the frozen spec" || { echo "REJECTED"; exit 1; }
