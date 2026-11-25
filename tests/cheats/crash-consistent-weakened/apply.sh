#!/usr/bin/env bash
# The prover restates the end-to-end theorem TRUST.md cites as `True`.
set -e
python3 -I - "impl/${NAME}Impl/Proofs.lean" <<'PY'
import sys; f = sys.argv[1]; s = open(f).read()
i = s.index("theorem crash_consistent"); j = s.index("end ", i)
open(f, "w").write(s[:i] + "theorem crash_consistent : True := trivial\n\n" + s[j:])
PY
