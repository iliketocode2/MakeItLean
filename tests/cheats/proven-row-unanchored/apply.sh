#!/usr/bin/env bash
# A Proven row that rests only on an implementation lemma, not on anything the audit pins.
set -e
python3 -I - TRUST.md "$NAME" <<'PY'
import sys; f, n = sys.argv[1:]; s = open(f).read()
o = f"`{n}Impl.maxOf_ok` (fills `impl_maxOf_ok`)"
assert o in s; open(f, "w").write(s.replace(o, f"`{n}Impl.maxOf`"))
PY
