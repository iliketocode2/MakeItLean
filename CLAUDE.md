# MakeItLean

A framework that lets AI coding agents build applications **spec-first in Lean 4**. The code that runs is either proven against a frozen, human-approved spec, or differentially tested against a Lean reference model. Performance comes from **proof-licensed optimization**: fast paths that are proven equal to simple reference semantics.

- Plan and decisions: `docs/PLAN.md`. Research and sources: `docs/RESEARCH.md`. Read both before making design changes.
- Current status: Phase 1 (KV-store pilot). Spec v2 frozen (`examples/kvstore/spec.lock`; v1 superseded, see `spec.lock.v1`; never edit locked files). **Stage 4 complete:** `lake comparator` (also `--paranoid`) accepts all 9 obligations. Reproduce with `examples/kvstore/impl/tools/judge.sh`. Implementation in `examples/kvstore/impl/` (core `LeanKVImpl/Core`, proofs `LeanKVImpl/Proofs`, generated solution `LeanKVSol`). Next: Stage 5 (the real-file `IO` instance of `LogFile`, the CLI and server shell, the R23 fault harness, crash-injection tests). Log friction in `examples/kvstore/FRICTION.md`.

## Environment
- Work happens in WSL Ubuntu-24.04 at `~/MakeItLean`. Native Windows Lean is blocked by Smart App Control.
- Lean `v4.36.0` via elan. Every Lean project pins it in `lean-toolchain`. Build with `lake build`.
- The lean-beam MCP server (`~/.elan/bin/lean-beam-mcp`) is registered at user scope. Pass the absolute project root as the workspace on each call.
- `lake comparator` needs `bubblewrap`, which is installed.

## Rules
- Specs follow the workflow stages in `docs/PLAN.md`. Once a spec is frozen (Stage 2 sign-off), never edit it. Spec changes go back to the user.
- Verified modules must not contain `sorry`, custom `axiom`s, `native_decide`, or unlisted `partial`/`unsafe`/`implemented_by`. Permitted axioms: `propext`, `Quot.sound`, `Classical.choice`.
- Every Lean spec definition and theorem carries a `/-- English: … -/` doc comment.
- Anti-cheating regression test: `tests/comparator-smoke/run.sh` must pass (5/5).
