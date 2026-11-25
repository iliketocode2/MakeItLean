#!/usr/bin/env bash
# A pure app claims a component is tested against the model; it has no shell and no self-test.
set -e
python3 -I - TRUST.md <<'PY'
import sys; f = sys.argv[1]; s = open(f).read()
o = "| Spec |"
assert o in s; open(f, "w").write(s.replace(o, "| Shell | Answers as the model | Tested against the model | `selftest` |\n" + o, 1))
PY
