#!/usr/bin/env bash
# Ledger Stage 5 tests: build the CLI, then run the CLI and crash tests on real files.
set -euo pipefail
cd "$(dirname "$0")"
lake build ledgerCli >/dev/null
tests/cli_test.sh
python3 tests/kill_test.py 300 1
python3 tests/kill_test.py 300 2
