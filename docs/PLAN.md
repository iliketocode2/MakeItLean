# MakeItLean — Plan (draft v1, 2026-11-20)

Background and sources are in [RESEARCH.md](RESEARCH.md).

## Goal
A framework that any coding agent (Claude Code, Codex, Cursor, …) can be attached to in order to build applications **spec-first in Lean 4**:
- **Correctness is proven.** The code that runs is the code the theorems are about, or is differentially tested against it.
- **Performance comes from proof-licensed optimization.** The spec states simple semantics. Agents may use any fast path they can prove (or, at a C/IO boundary, differentially test) equal to that semantics.

## Decisions so far
| Topic | Decision |
|---|---|
| What is guaranteed | Functional correctness (proven), plus optimizations justified by proven invariants (as in the $12-server entries). Wall-clock speed is benchmarked, not proven. Cost-model theorems are optional per project. |
| Implementation language | **Hybrid.** Lean holds the spec and a runnable reference model always. The core is in Lean where viable, generic over an effect/storage interface. Hot leaves or shells may be C, Rust or TypeScript, gated by differential tests against the Lean definitions. |
| First pilot | Key-value store / mini DB |
| Human role | The user reviews a **side-by-side spec**: plain-English requirement next to each Lean definition and theorem. The framework must generate that rendering. |
| Agents supported | Agent-agnostic (`AGENTS.md`), with Claude Code configs and skills as the first-class path |
| `mil` CLI language | **Lean 4, no external dependencies** (decided 2026-11-22, replacing `leanprover/Cli`: toolchain churn broke four APIs during the pilot). The framework is built with itself. Its own logic (spec-lock hashing, gate sequencing, trust-manifest generation) is a candidate for the framework's own specs and proofs. |
| Environment | Native Windows runs elan 4.4.0 with Lean 4.36.0, but **Smart App Control blocks the unsigned `libleanshared.dll`** (CodeIntegrity events 3033/3077, exit 0xC0E90002). **Decision: develop in WSL Ubuntu-24.04**, where elan and Lean 4.36.0 are installed. Phase-0 comparator smoke test passed on 2026-11-20: the honest solution exits 0; `sorry`, a custom axiom, a weakened statement and a redefined spec definition are each rejected with exit 1. That first run used `--inadvisably-no-sandbox`. `bubblewrap` is now installed, and on 2026-11-21 `tests/comparator-smoke/run.sh` passed 5/5 sandboxed. |

| What was built vs. this plan (reconciled 2026-11-25, Phase 5 W3) | **Effect/Store classes** (`class Effects m`, `class Store m` in `lean/`): superseded by the **LeanKV substrate** (decided 2026-11-22). Apps map each command onto LeanKV through `pick`, and `app_crash_consistent` gives them durability. **Bytes and fast-path library:** stays in LeanKV (`LeanKVImpl.Proofs.*`), indexed in `knowledge/LEMMAS.md`, until a second binary format needs it. **Extern-leaf and self-test macros:** not built; each app's differential test (`tools/difftest.py`) and planted bugs do this job (see the Stage 5 row). **Cost/Tick monad:** optional, not built. **`mil` built with itself:** not done (user decision 2026-11-25). The comparator and the kernel, not `mil`, make proofs trustworthy, so `mil` gets negative tests instead. |
| Judge workspace (2026-11-25, Phase 5 W1) | No longer the repository root. `mil judge` copies one app's packages to a temporary workspace and runs `lake comparator` there. Apps outside the checkout fetch the framework by a pinned git `require` (W2). |

## Core architecture: the pattern every app follows

```
REQUIREMENTS.md  ──►  Spec/ (Lean)  ──►  [validate + human sign-off + freeze]
                        │  simple reference semantics (lists, sorts, maps)
                        │  properties / end-to-end theorem statements
                        ▼
                     Core/ (Lean, generic in `class Effects m` / `class Store m`)
                        │                         │
                 instance Model (pure state)   instance IO (real effects)
                        │                         │
                 Proofs/: core ≡ spec         Leaves/: @[extern] C/Rust, each on a Lean definition
                                                   │
                                            SelfTest: differential random tests + injected-bug mutations
                        ▼
                     Audit gate → TRUST.md (proven / tested / assumed)
```

The pattern comes from the soonhokong entry. The handler is written once, generic in `Store m`, proven in `Store Model` and run as `Store IO`.

## Workflow stages and gates
Each gate is a scripted check. An agent cannot move to the next stage until its gate passes.

| # | Stage | Output | Gate |
|---|---|---|---|
| 0 | Intent | `REQUIREMENTS.md`: plain English, concrete examples, non-goals | The user approves it |
| 1 | Spec | `Spec/*.lean`: types, reference semantics, theorem *statements* with `sorry`. Every definition and theorem carries a `/-- English: … -/` doc. | Builds; every declaration has an English doc |
| 2 | Spec validation | `#guard` examples from the requirements; Plausible properties against the reference model; non-vacuity lemmas (preconditions are satisfiable, postconditions can fail); a **spec-critic agent** that writes wrong implementations the spec must reject | All pass, then the generated `SPEC_REVIEW.md` is shown side by side. **The user signs off and the spec is frozen** (hash recorded in `spec.lock`; comparator challenge file generated) |
| 3 | Implement | `Core/`, generic over the effect class, plus the `Model` instance | Builds |
| 4 | Prove | `Proofs/`: the end-to-end theorem(s) and the fast-path ≡ reference-semantics lemmas | No `sorry` |
| 5 | Boundary | The `IO` instance and `@[extern]` leaves; a self-test harness (N random inputs, leaf vs Lean definition, IO store vs Model); mutation injection | Self-test passes and every injected mutation is caught |
| 6 | Audit | `lake comparator` against the frozen spec; axiom whitelist; ban `sorry`, `native_decide`, custom `axiom`, and unlisted `partial`/`unsafe`/`implemented_by`; re-check the theorems with leaves made opaque; generate `TRUST.md` | All green; this is the CI gate |
| 7 | Optimize | Benchmarks. Each optimization lands only with a proof or a differential test (and optionally a cost-model theorem). | No regressions; gate 6 still green |

If a proof keeps failing or a counterexample turns up, the work goes **back to stage 2**. Agents never edit the frozen spec. Changing it is a new sign-off.

## Framework deliverables (repo layout, proposed)
```
MakeItLean/
  lean/MakeItLean/        Lean library: Effect/Store patterns, Model state monad helpers,
                          spec-doc attributes (English pairing), non-vacuity helpers,
                          extern-leaf + self-test macros, optional Cost/Tick monad
  cli/                    `mil` CLI: init | spec-review | freeze | validate | verify | selftest | audit | trust
  agents/                 AGENTS.md (universal), CLAUDE.md, role prompts (spec-author, spec-critic,
                          implementer, prover, auditor), Claude Code skills, MCP config (lean-lsp-mcp)
  templates/app/          Project skeleton (lakefile, lean-toolchain pin, Spec/Core/Proofs/Leaves/SelfTest)
  knowledge/              Shared verified lemmas + idea notes (verified / promising / dead end),
                          after the DeepMind wiki
  examples/kvstore/       The pilot
  docs/
```

## Phases
**Phase 0: environment (small).**
- Set up WSL2 Ubuntu, elan, a pinned Lean stable toolchain, and lean-lsp-mcp registered in Claude Code. Work from a WSL path with no spaces.
- Smoke test: a toy spec, one honest solution and three cheating solutions (`sorry`, `axiom`, a weakened statement).
- *Exit:* `lake comparator` accepts the honest one and rejects all three.

**Phase 1: pilot by hand (KV store).** I act as the agent, following the workflow above by hand and logging every point of friction. Proposed v1 scope:
- **API:** `put`, `get`, `delete`, `range(lo, hi, limit)`, and atomic `batch`.
- **Reference semantics:** a sorted association list. The end-to-end theorem says that any operation sequence answers exactly as the reference does.
- **Fast path:** a Lean B-tree or weight-balanced tree, proven ≡ the reference.
- **Durability:** an append-only log with replay. Prove `replay (encode ops) = fold ops`. The filesystem is an `IO` instance, so it is *trusted and tested* with crash-injection tests.
- **Interface:** a CLI first, optionally an HTTP interface later through a C/`Std.Http` leaf.
- **Proof-licensed optimization:** for example, prove that a batch is equivalent to serial execution, then do group commit; or prove range-scan correctness on the tree's in-order traversal.

**Phase 2: extract the framework.**
- Turn what the pilot needed into the library, the CLI, templates and agent instructions.
- *Exit:* a **fresh agent session that uses only the framework** rebuilds a variant of the pilot, or a second small app, without my hand-holding.
- Decided 2026-11-22: the exit app is a **double-entry bank ledger** (a new durable app), built by a fresh subagent in a git worktree. Plan: [PHASE2.md](PHASE2.md).
- **Exit test passed 2026-11-22:** the subagent delivered `examples/ledger/` (AUDIT PASSED, re-run independently). Post-test framework fixes come before Phase 3; see [PHASE2.md](PHASE2.md).

**Phase 3: hybrid and multi-agent.**
- A second app with a non-Lean shell (for example, a TypeScript or Rust HTTP layer) checked by differential tests against the Lean model.
- Separate agent roles with write permissions enforced, so the implementer cannot touch `Spec/`.
- The knowledge base.

**Phase 4: evaluation.**
- Measure on a subset of VERINA or FVAPPS.
- Try Codex and Cursor through `AGENTS.md`.
- Optional prover back ends: Leanstral, Aristotle.

## Main risks
1. **Spec gap.** This is the biggest risk. Mitigations: the side-by-side review, a spec-critic agent, non-vacuity checks and examples.
2. **Proof effort.** Benchmarks show Lean code proofs remain hard (VERINA: 5% of proofs). The soonhokong entry has 14.8k lines of proof for 1.9k lines of code. Mitigations:
   - prefer simple reference semantics, `grind`, `omega` and `bv_decide`;
   - keep proofs about pure cores;
   - accept "tested" in `TRUST.md` where proof is too costly.
3. **Toolchain churn** (monthly releases, renames such as `mvcgen`→`vcgen`). Mitigations: pin per project and keep a bump procedure.
4. **Windows friction.** Mitigation: WSL2.
5. **The trusted base** (Lean compiler/runtime, C leaves, OS). It is documented in `TRUST.md` and fuzzed. lean-zip found a heap overflow in Lean's runtime this way.
