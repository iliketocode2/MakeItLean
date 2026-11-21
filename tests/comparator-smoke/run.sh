#!/usr/bin/env bash
# Regression test for the anti-cheating gate: the honest solution must pass and
# every cheat must be rejected by `lake comparator` (sandboxed; needs bubblewrap).
set -u
cd "$(dirname "$0")"
lake build Challenge Honest CheatSorry CheatAxiom CheatWeaken CheatRedefine >/dev/null 2>&1 || { echo "build failed"; exit 2; }
fail=0
for m in Honest CheatSorry CheatAxiom CheatWeaken CheatRedefine; do
  cat > ".comparator-$m.json" <<J
{"challenge_module":"Challenge","solution_module":"$m","theorem_names":["fastSum_correct"],
 "definition_names":["fastSum"],"permitted_axioms":["propext","Quot.sound","Classical.choice"]}
J
  lake comparator --config=".comparator-$m.json" >/dev/null 2>&1; rc=$?
  if [ "$m" = Honest ]; then want=0; else want=1; fi
  if [ $rc -eq $want ]; then echo "PASS $m (exit $rc)"; else echo "FAIL $m (exit $rc, wanted $want)"; fail=1; fi
done
exit $fail
