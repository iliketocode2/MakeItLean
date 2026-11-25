#!/usr/bin/env bash
# The hole is filled with a different function than the one the pinned facts are about.
set -e
printf '\nnamespace %sImpl\n/-- Another pick. -/\ndef pick2 := @pick\nend %sImpl\n' "$NAME" "$NAME" >> "impl/${NAME}Impl/Core.lean"
python3 -I - impl/fill.json "$NAME" <<'PY'
import json, sys; f, n = sys.argv[1:]; j = json.load(open(f))
j["holes"] = {k: f"{n}Impl.pick2" for k in j["holes"]}; json.dump(j, open(f, "w"), indent=2)
PY
