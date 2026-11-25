#!/usr/bin/env bash
# The Q1 reproduction: compiled code differs from the proven body, and the app's own audit.lean
# (which mil no longer reads) is cut to its imports.
set -e; . "$ROOT/tests/cheats/lib.sh"
implemented_by_core
printf 'import %sImpl.Proofs\n' "$NAME" > impl/audit.lean
