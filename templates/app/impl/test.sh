#!/usr/bin/env bash
# Stage 5 tests: build the CLI, then run the CLI and crash tests on real files.
set -euo pipefail
cd "$(dirname "$0")"
lake build appnameCli >/dev/null
tests/cli_test.sh
python3 tests/kill_test.py 200 1
