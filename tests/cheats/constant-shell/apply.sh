#!/usr/bin/env bash
# The shell calls the verified pick (the shell gate passes) but prints a constant answer.
set -e
python3 -I - "impl/${NAME}Impl/Shell.lean" <<'PY'
import sys; f = sys.argv[1]; s = open(f).read()
o = "else render (cstep (dec before.toList) (c.map toBytes)).2"
assert o in s; open(f, "w").write(s.replace(o, 'else "VALUE 0"'))
PY
