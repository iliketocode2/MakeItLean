#!/usr/bin/env bash
# Stage 5 tests: build the CLI and the model oracle, then run the CLI, crash and differential tests.
set -euo pipefail
cd "$(dirname "$0")"
lake build counterCli counterOracle >/dev/null
tests/cli_test.sh
python3 tests/kill_test.py 200 1
# `serve` (the real store on real files, through the trusted shell) against the spec's model
B="$PWD/.lake/build/bin"
python3 -I ../../../tools/difftest.py --sut "$B/counter {dir} serve" --oracle "$B/counter-oracle" \
  --gen tests/gen_commands.py --runs 30 --length 200
