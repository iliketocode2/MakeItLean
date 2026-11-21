#!/usr/bin/env bash
# CI gate: the frozen spec files must be byte-for-byte what was signed off.
set -euo pipefail
cd "$(dirname "$0")/.."
[ -e spec.lock ] || { echo "no spec.lock: spec not frozen yet"; exit 1; }
grep -v '^#' spec.lock | sha256sum --check --quiet && echo "spec.lock OK"
