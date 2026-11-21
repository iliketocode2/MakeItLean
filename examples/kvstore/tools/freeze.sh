#!/usr/bin/env bash
# Stage 2 freeze: run only after the user signs off on SPEC_REVIEW.md.
# Builds the spec (English-doc gate + #guard examples), regenerates SPEC_REVIEW.md, and records
# the SHA-256 of every file the frozen spec consists of in spec.lock.
set -euo pipefail
cd "$(dirname "$0")/.."
[ -e spec.lock ] && { echo "spec.lock already exists: the spec is frozen. Spec changes need a new sign-off."; exit 1; }
lake build LeanKVSpec >/dev/null
python3 tools/spec_review.py >/dev/null
{
  echo "# LeanKV frozen spec. Signed off by: ${SIGNED_OFF_BY:?set SIGNED_OFF_BY} on $(date -u +%Y-%m-%d)"
  sha256sum lean-toolchain lakefile.lean comparator.json LeanKV/Spec.lean LeanKV/Spec/*.lean \
    LeanKV/Tools/EnglishDocs.lean SPEC_REVIEW.md
} > spec.lock
echo "Frozen. spec.lock:"; cat spec.lock
