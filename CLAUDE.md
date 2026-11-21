# MakeItLean

A framework that lets AI coding agents build applications **spec-first in Lean 4**. The code that runs is either proven against a frozen, human-approved spec, or differentially tested against a Lean reference model. Performance comes from **proof-licensed optimization**: fast paths that are proven equal to simple reference semantics.

- Plan and decisions: `docs/PLAN.md`. Research and sources: `docs/RESEARCH.md`. Read both before making design changes.
- Current status: Phase 1 (KV-store pilot). The spec is frozen (`examples/kvstore/spec.lock`, signed off 2026-11-21; check with `tools/check_lock.sh`; never edit locked files). Stage 3 (implementation) is done in the separate package `examples/kvstore/impl/` (module root `LeanKVImpl`; differential tests in `impl/test.sh`). Next is Stage 4: prove the 9 obligations for the core. Log friction in `examples/kvstore/FRICTION.md`.

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
