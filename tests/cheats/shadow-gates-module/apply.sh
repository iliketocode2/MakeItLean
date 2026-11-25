#!/usr/bin/env bash
# The implementation ships its own MakeItLean.Gates module.
set -e; . "$ROOT/tests/cheats/lib.sh"
implemented_by_core
neutered_gates /tmp/mil-cheat-gates.$$
mkdir -p impl/MakeItLean; cp /tmp/mil-cheat-gates.$$/MakeItLean/Gates.lean impl/MakeItLean/Gates.lean
rm -rf /tmp/mil-cheat-gates.$$
