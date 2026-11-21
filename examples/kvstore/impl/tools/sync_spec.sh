#!/usr/bin/env bash
# Copy the frozen spec package into impl/spec (the comparator sandbox only sees this package's
# directory) and verify every copied file against spec.lock.
set -euo pipefail
cd "$(dirname "$0")/.."
rm -rf spec && mkdir -p spec
cp -r ../LeanKV ../lakefile.lean ../lean-toolchain ../comparator.json ../SPEC_REVIEW.md spec/
rm -rf spec/LeanKV/SpecCritic
if [ -e ../spec.lock ]; then
  cp ../spec.lock spec/
  (cd spec && grep -v '^#' spec.lock | sha256sum --check --quiet) && echo "impl/spec synced; matches spec.lock"
else
  echo "WARNING: spec is NOT frozen (no spec.lock); synced the working copy"
fi
