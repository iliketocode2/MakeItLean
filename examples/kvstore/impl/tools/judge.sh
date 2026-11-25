#!/usr/bin/env bash
# Stage 4/6 verdict: check the frozen spec's lock, regenerate the solution, build, and let
# `lake comparator` (sandboxed; --paranoid with PARANOID=1) judge all obligations against the
# frozen spec. The comparator runs in a staged judge workspace (`mil comparator`: a temporary copy
# of only LeanKV's packages). Exit 0 = accepted.
set -euo pipefail
IMPL="$(cd "$(dirname "$0")/.." && pwd)"
ROOT="$(cd "$IMPL/../../.." && pwd)"
MIL="$ROOT/cli/.lake/build/bin/mil"
"$IMPL/../tools/check_lock.sh" >/dev/null
( cd "$IMPL" && python3 tools/make_solution.py >/dev/null && lake build >/dev/null )
CFG="$(mktemp --suffix=.json)"; trap 'rm -f "$CFG"' EXIT
python3 - "$IMPL/../comparator.json" "$CFG" <<'PY'
import json, sys; c = json.load(open(sys.argv[1])); c["solution_module"] = "LeanKVSol.Holes"
json.dump(c, open(sys.argv[2], "w"), indent=1)
PY
"$MIL" comparator ${PARANOID:+--paranoid} "$IMPL" "$CFG" >/dev/null 2>&1 \
  && echo "ACCEPTED: all obligations proven against the frozen spec" || { echo "REJECTED"; exit 1; }
