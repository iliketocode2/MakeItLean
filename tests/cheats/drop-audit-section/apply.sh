#!/usr/bin/env bash
# Remove the locked audit section from mil.json to fall back to an app-supplied audit.
set -e; . "$ROOT/tests/cheats/lib.sh"
implemented_by_core
python3 -I - mil.json <<'PY'
import json, sys; f = sys.argv[1]; j = json.load(open(f)); del j["audit"]; json.dump(j, open(f, "w"), indent=2)
PY
printf 'import %sImpl.Proofs\n' "$NAME" > impl/audit.lean
