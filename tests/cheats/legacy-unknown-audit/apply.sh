#!/usr/bin/env bash
# An app frozen without an audit section, whose own audit.lean is not in lean/legacy_audits.json.
set -e; . "$ROOT/tests/cheats/lib.sh"
implemented_by_core
python3 -I - mil.json <<'PY'
import json, sys; f = sys.argv[1]; j = json.load(open(f)); del j["audit"]; json.dump(j, open(f, "w"), indent=2)
PY
rm spec.lock; "$MIL" freeze mil.json cheat >/dev/null
printf 'import %sImpl.Proofs\n' "$NAME" > impl/audit.lean
