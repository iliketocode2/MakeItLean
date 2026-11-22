# Phase 2: extracting the framework (started 2026-11-22)

**Exit test** (from PLAN.md): a fresh agent, given only the framework and a one-paragraph brief, builds a **new durable app, a double-entry bank ledger**, without help. It runs as a subagent in an isolated git worktree; the user approves its requirements and spec at the sign-off gates.

**Decisions (user, 2026-11-22):** a new app (ledger), not a LeanKV variant; the exit test is a fresh subagent in a worktree; `mil` is plain Lean with no external dependencies.

## Work breakdown, traced to the pilot's friction log (`examples/kvstore/FRICTION.md`)

| # | Deliverable | Contents | Friction it answers |
|---|---|---|---|
| 1 | `lean/` package `makeitlean`: **gates** | `#assert_english_docs`, `#assert_holes_only_in_theorems`, `#assert_spec_axioms` (theorems naming a hole may be open; all others clean), `#audit_verified` (axioms; no sorry/unsafe/partial/opaque/implemented_by/extern; shell not imported); each with a negative test | doc gate false positives; holes in definitions (v1 spec flaw); `partial` compiles to `opaque`; gates need negative tests |
| 2 | `lean/` **bytes and fast-path library** | `toBytes`/`ofBytes` and the `ByteArray` lemma set; "array loop ≡ list fold" and "`ByteArray` builder ≡ list concatenation" lemmas | `ByteArray.toList` has no lemmas; proof-licensed optimizations were near-free once these existed |
| 3 | `lean/` **generic durable store** | Spec: a state machine with a logged-entry codec; the log format (magic, byte stuffing, length, CRC-32C); `recover`; the model file system and crash model; sessions. Proven once: canonical decoding, torn tail, corruption, crash consistency, no-fault correctness. Implementation: `ByteArray` codec, tail-recursive recovery, a store generic over `LogFile m`, the C file leaf, the real-file instance. An app supplies its machine, entry codec, and their obligations | most of LeanKV's 3,000 proof lines; canonical decoding; stack depth; no `fsync` in Lean |
| 4 | `cli/` **`mil`** (Lean, no dependencies) | `init`, `review` (generated from the elaborated environment, not source text), `freeze`/`check-lock` (including the framework version), `solution` (generate the comparator solution), `judge`, `audit` | review generator mis-parsed source text; comparator sandbox only sees the package directory; solution modules cannot import the spec's holes |
| 5 | `templates/app/` | Separate `spec/` and `impl/` packages with distinct module roots; `exeName` targets; differential, harness, limits and benchmark skeletons with the known traps handled | `lakefile` in the lock; module-root collisions; target names; hoisted benchmarks |
| 6 | `agents/` | `AGENTS.md` (workflow, stages, gates, rules), role prompts (spec author, spec critic, implementer, prover, auditor), Claude Code skill | reviewers need the document, not a summary; "what in the spec can see this requirement?" |
| 7 | `knowledge/` | Lean 4.36 proof idioms and traps; distilled lessons; index of reusable proven lemmas | recurring tactic and API traps |
| 8 | **Exit test** | The ledger brief; run the subagent; record its friction | — |

## Progress log

- 2026-11-22: **Decision (user):** durability for new apps comes from **LeanKV as a substrate** (option B), not a generic durable machine (option A, deferred). An app keeps its state in the LeanKV store and turns each command into one KV command via `pick`. Deliverable 3 is therefore the substrate API, not a re-proof of the log.
- 2026-11-22: **Deliverable 1 done:** `lean/MakeItLean/Gates.lean` (English-doc, hole, spec-axiom gates; verified-code audit), with negative and positive tests in `lean/MakeItLeanTest/` frozen via `#guard_msgs`. `lake build` in `lean/` runs them.
- 2026-11-22: **Deliverable 3 (substrate) done:** `Core.execPick` (`examples/kvstore/impl/LeanKVImpl/Core/Substrate.lean`) and `substrate_crash_consistent` / `substrate_no_faults` (`Proofs/Substrate.lean`). For any app with `PickOk pickI pick`, a session answers like `runPick pick` and is crash-consistent, using only the standard axioms.
- 2026-11-22: **Judge workspace at the repository root** (`lakefile.lean` + `judge/`). The comparator sandbox only sees the package it runs in, so the root requires every app package. LeanKV's `impl/spec` copy was removed (it caused duplicate `leankv` sources once a second app depended on LeanKV); LeanKV's `judge.sh` now runs from the root and is still ACCEPTED.
- 2026-11-22: **`PickOk` now assumes a well-formed index** (lookups only agree with the reference on well-formed trees, and the store only ever holds those).
- 2026-11-22: **Worked example `examples/counter/`** on the substrate. The spec has a reference model, a storage layout, a reference `pickRef` and a proven refinement theorem; one hole `Impl.pick`. Downstream apps import LeanKV's library spec `LeanKVSol.Base.*` (hole-free copies, verified by LeanKV's comparator run), not `LeanKV.Spec.*`, which would clash with LeanKV's core. **`mil judge` ACCEPTS Counter.** The `counter` CLI works on real files (the C leaf links across packages).
- 2026-11-22: **Deliverable 4 (part):** `cli/` `mil` in plain Lean, with `init`, `solution`, `judge [--paranoid]`, `freeze`, `check-lock` and `review`. `review` depends on `MakeItLean.Review`, which is still to write.
- **Next:** `MakeItLean.Review`; `templates/app` (generalized from Counter); `agents/`; `knowledge/`; then the exit test.
- 2026-11-22: **Deliverables 1–7 in place.**
  - `lean/MakeItLean/Review.lean`: `#spec_review`, behind `mil review`; generates SPEC_REVIEW.md from the elaborated spec.
  - `mil audit` runs the lock check, spec gates, comparator `--paranoid` and `#audit_verified`. **Counter: AUDIT PASSED.**
  - `templates/app` is the Counter app with its names as placeholders. `mil init` copies it, registers the app in the judge workspace and updates the manifest. A fresh `mil init` app is ACCEPTED by `mil judge` with no edits (tested twice, then removed).
  - `agents/AGENTS.md`: the substrate pattern, stages and gates, hard rules, roles, commands.
  - `knowledge/LEAN_IDIOMS.md` and `knowledge/LEMMAS.md`.
- **Next: the exit test** (needs Phase 2 committed, since a worktree only sees commits). The subagent works alone in a worktree. At Stage 0 and Stage 2 it stops and reports, the user's approval is relayed verbatim, and I add no help.
