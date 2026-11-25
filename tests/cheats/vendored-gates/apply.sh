#!/usr/bin/env bash
# The Q3 reproduction: the impl lakefile requires a vendored framework copy with a no-op audit.
set -e; . "$ROOT/tests/cheats/lib.sh"
implemented_by_core
neutered_gates impl/vendor_lean
sed -i "s|^require ${NAME,} from \"..\"|require makeitlean from \"vendor_lean\"\n&|" impl/lakefile.lean
grep -q vendor_lean impl/lakefile.lean
(cd impl && lake update >/dev/null 2>&1)
