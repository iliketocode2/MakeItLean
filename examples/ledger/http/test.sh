#!/usr/bin/env bash
# Tests of the Ledger HTTP API (http/REQUIREMENTS.md §8, V2–V6, V8).
# Usage: examples/ledger/http/test.sh   (needs Node.js 24+, python3, and `lake` for the ledger)
# V1 (serve against the model) is impl/tests/serve_test.sh; V7 is impl/test.sh and `mil audit`.
set -euo pipefail
cd "$(dirname "$0")"
H="$PWD"
B="$H/../impl/.lake/build/bin"
(cd ../impl && lake build ledgerCli ledgerOracle >/dev/null)

# V8: Node.js standard library only. Every import is `node:` or a relative file of this
# directory; there is no package.json and no node_modules.
bad="$(grep -hoE "^import .* from '[^']*'" ./*.ts tests/*.ts | grep -vE "from '(node:[a-z_/]+|\./[a-z_/]+\.ts)'" || true)"
if [[ -n "$bad" || -e package.json || -e node_modules ]]; then
  echo "V8 FAIL: non-standard imports or packages: $bad"; exit 1
fi
echo "V8: every import is node: or local ($(grep -hE "^import " ./*.ts tests/*.ts | wc -l) imports), no package.json, no node_modules"

# V2: the HTTP API against the frozen model, through the adapter (30 runs x 200, two seeds).
for seed in 1 2; do
  python3 -I ../../../tools/difftest.py --sut "node $H/adapter.ts {dir}" --oracle "$B/ledger-oracle" \
    --gen ../impl/tests/gen_commands.py --runs 30 --length 200 --seed "$seed"
done
# V3: planted bugs make V2 fail.
node tests/planted_bug.ts
# V4: the literal examples E1–E35, byte for byte.
node tests/replay.ts
# V5: HTTP-only cases (413, malformed requests, startup, shutdown, fail-stop).
node tests/edge_test.ts
# V6: kill test, 2 runs x 300 requests (H-D9).
node tests/kill_test.ts 2 300 1
echo "http/test.sh: all passed"
