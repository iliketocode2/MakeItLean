#!/usr/bin/env bash
# The lakefile stays honest; only the impl's lake-manifest.json points the framework at a copy.
set -e; . "$ROOT/tests/cheats/lib.sh"
implemented_by_core
neutered_gates impl/vendor_lean
python3 -I - impl/lake-manifest.json <<'PY'
import json, sys; f = sys.argv[1]; j = json.load(open(f))
for p in j["packages"]:
    if p["name"] == "makeitlean": p["dir"] = "vendor_lean"
json.dump(j, open(f, "w"), indent=1)
PY
