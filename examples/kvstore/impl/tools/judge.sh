#!/usr/bin/env bash
# Stage 4/6 verdict: sync the frozen spec (verified against spec.lock), regenerate the solution,
# build everything, and let `lake comparator` (sandboxed, plus --paranoid external kernels) judge
# all obligations against the frozen spec. Exit 0 = accepted.
set -euo pipefail
cd "$(dirname "$0")/.."
tools/sync_spec.sh
python3 tools/make_solution.py
python3 - <<'PY'
import json; c = json.load(open("spec/comparator.json")); c["solution_module"] = "LeanKVSol.Holes"
json.dump(c, open("comparator.json", "w"), indent=1)
PY
lake build >/dev/null
lake build LeanKV.Spec LeanKVSol.Holes >/dev/null
lake comparator --config=comparator.json ${PARANOID:+--paranoid} >/dev/null 2>&1 && echo "ACCEPTED: all obligations proven against the frozen spec" || { echo "REJECTED"; exit 1; }
