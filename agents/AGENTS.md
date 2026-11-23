# MakeItLean — instructions for coding agents

You are building an application **spec-first in Lean 4**. The code that runs must be *proven* against a spec the user approved and froze, or differentially *tested* against it. An external judge (`lake comparator`) checks the proofs; you cannot talk your way past it. Read this whole file before starting, then [knowledge/LEAN_IDIOMS.md](../knowledge/LEAN_IDIOMS.md) and [knowledge/LEMMAS.md](../knowledge/LEMMAS.md).

## Environment
- Linux/WSL. Lean `v4.36.0` (pinned in every `lean-toolchain`). Build with `lake build`. No Mathlib.
- `mil` is the framework CLI: `~/MakeItLean/cli/.lake/build/bin/mil` (build it with `cd cli && lake build` if missing).
- The repository root is the **judge workspace** (`lakefile.lean`, `judge/`). Apps live in `examples/<app>/`.

## The pattern: an app on the LeanKV substrate
Durable apps keep their state in **LeanKV**, a proven ordered key-value store (`examples/kvstore/`). Each app command becomes **exactly one KV command** (a read, or one atomic `put`/`delete`/`batch`), chosen by a function `pick` from the current store contents. The app proves two things: its reference translation `pickRef` refines its model (`pickRef_refines`, in the spec), and its fast `pick` equals `pickRef` (the obligation). LeanKV's `app_crash_consistent` then turns those into the app's own end-to-end theorem, `<App>Impl.crash_consistent` (already written in the template's `Proofs.lean`): after any crash, the store decodes to the model after exactly the acknowledged commands, plus possibly the one in flight.

The worked example is **`examples/counter/`**. Read it end to end before writing anything; your app has the same shape.

| File | What goes in it |
|---|---|
| `REQUIREMENTS.md` | Stage 0: plain English, IDs R1…, examples, non-goals, storage layout. |
| `<App>/Spec/Model.lean` | The reference model: commands (generic in the byte type `β`, with a `map`), answers, the state, `cstep : State → Cmd Bytes → State × Answer`. **State shape:** a function is simplest, but if any requirement sums or lists the state (a total, a listing), use a sorted list of (key, value) pairs that mirrors LeanKV's `Store`. **Rule shape:** put the command rules in one decision function that takes the *lookup* as a parameter; `cstep` and `pickRef` both call it, and the implementation calls it with a fast lookup, which makes the obligation proof short (the ledger's was about 20 lines). Then the **storage layout**: how state maps to KV keys and values, `dec : Store → State` (what a KV store stands for), the value codecs, and the reference translation `pickRef : Store → Cmd Bytes → LeanKV Cmd Bytes`. Then the **Stage 2 theorems**: codec round trips and `pickRef_refines` (on every well-formed store, running `pickRef`'s KV command changes `dec` exactly as `cstep` does). |
| `<App>/Spec/Properties.lean` | Requirement-level theorems (all-or-nothing, bounds, conservation…), each stated from the empty state through any command sequence, and every worked example from `REQUIREMENTS.md` as a `#guard`. In the lock. |
| `<App>/SpecCritic/*.lean` | The spec critic's planted wrong implementations and models, each rejected by a `#guard`. Not locked. `mil review` shows these and the examples to the reviewer. |
| `<App>/Spec/Contract.lean` | **Only** the implementation hole(s) and their obligations. Keep holes in this separate file. `def Impl.pick : Tree → Cmd ByteArray → LeanKV.Spec.Cmd ByteArray := sorry` and `theorem impl_pick_ok … : (Impl.pick t c).map toBytes = pickRef t.toList (c.map toBytes) := sorry`. |
| `<App>/Spec.lean` | Imports plus the three gates (`#assert_english_docs`, `#assert_holes_only_in_theorems`, `#assert_spec_axioms`). |
| `impl/<App>Impl/Core.lean` | The implementation of `pick` on the in-memory `Tree`, reading it with `LeanKV.Core.lookup` (proven equal to the reference lookup). |
| `impl/<App>Impl/Proofs.lean` | The proof of the obligation (see `CounterImpl.pick_ok`: `toList_lookup` bridges `Core.lookup` to the spec), then `pickOk`, `refines` and `crash_consistent` (keep the template's; `impl/audit.lean` pins them to the frozen spec). |
| `impl/<App>Impl/Shell.lean` | The CLI: open the store on real files (`LeanKV.Shell.lkvOpen`, `RealM`), run `LeanKV.Core.execPick`, print answers. Trusted, not verified: keep it thin. |
| `mil.json` | Which files hold holes, the **names** of the holes and obligations, which files the lock covers. Locked at the freeze. |
| `impl/fill.json` | How each hole and obligation is filled (the Lean terms). Not locked, so Stage 4 never touches a frozen file. |
| `impl/test.sh`, `impl/tests/` | Stage 5: the CLI test (every example, error and limit) and the kill test. Skeletons from the template. |
| `TRUST.md` | Stage 6: each requirement proven / tested / trusted, citing theorem names (`mil audit` checks they exist). |

**Import `LeanKVSol.Base.*`** (LeanKV's hole-free library spec) for LeanKV types and lemmas, **never `LeanKV.Spec.*`**. The latter clashes with LeanKV's core.

## Workflow: stages and gates
Never skip a gate. Stages 0 and 2 end with **the user's explicit approval**. Ask, and wait.

| # | Stage | You do | Gate |
|---|---|---|---|
| 0 | Requirements | `mil init <App> examples/<app>`; write `REQUIREMENTS.md`. Mark open questions **[DECIDE]** and ask the user. | **User approves `REQUIREMENTS.md`.** Do not write Lean before this. |
| 1 | Spec | Write `Spec/Model.lean` and `Spec/Contract.lean`, replacing the counter example. Every declaration carries `/-- English: … -/`. Statements of Stage 2 theorems may be `sorry` for now. | `lake build` in the spec package: all three gates pass. |
| 2 | Validate and freeze | Prove every spec theorem that does **not** name a hole (codecs, refinement, `Properties.lean`). Add `#guard` examples from the requirements. Act as **spec critic** in `<App>/SpecCritic/`: plant wrong implementations and models, and check the spec rejects them. Run `mil review examples/<app>/mil.json`, show the user `SPEC_REVIEW.md`. | Spec-axiom gate: only obligations are open. **User signs off**, then `mil freeze examples/<app>/mil.json <user>`. After this, **never edit the files in `spec.lock`**; spec changes go back to the user for a new sign-off. |
| 3 | Implement | `impl/<App>Impl/Core.lean`. Test it against the spec by evaluation before proving (`#guard` over random commands). | `lake build` in `impl/`. |
| 4 | Prove | `impl/<App>Impl/Proofs.lean`; fill `impl/fill.json`. `mil judge` first checks that the spec's holes and obligations are exactly `mil.json`'s (`mil contract`). | `mil judge examples/<app>/mil.json` prints **ACCEPTED**. |
| 5 | Boundary | The CLI; real-file tests; tests at every size limit in the requirements (proofs do not bound stack or memory). | Tests pass. |
| 6 | Audit | `TRUST.md`: each requirement proven / tested / trusted, citing theorem names. Durability cites `<App>Impl.crash_consistent`. | `mil audit examples/<app>/mil.json` prints **AUDIT PASSED** (it requires `spec.lock` and checks every name `TRUST.md` cites). |

## Hard rules (each one was learned the hard way)
1. **Never edit a frozen spec** (files listed in `spec.lock`), and never edit `examples/kvstore/` or `lean/`. If the spec is wrong, stop and tell the user.
2. **Verified code** (Core, Proofs, the generated solution) may not contain `sorry`, custom `axiom`s, `native_decide`, `bv_decide`, `partial def`, `unsafe`, `opaque`, `@[implemented_by]` or `@[extern]`. Only `propext`, `Quot.sound`, `Classical.choice` are allowed. `mil audit` checks all of this on compiled code.
3. **Spec definitions never call a hole.** Only theorem statements name holes; a definition that needs the implementation takes it as a parameter. Otherwise the comparator rejects every solution (`#assert_holes_only_in_theorems` enforces this).
4. **Every spec declaration has an `English:` doc** that a non-expert can check against `REQUIREMENTS.md`.
5. **Ask "what in the spec can see this requirement?"** for every requirement. A property the spec cannot state (speed, resource use) is benchmarked or tested, and `TRUST.md` says so.
6. **Make the spec checkable.** Bound every number the app stores (for example, balances < 2⁶⁴) and say what happens at the bound. Prove codecs round-trip. Prefer functions over clever data structures in the model.
7. **Test before proving.** Evaluate each theorem statement on concrete inputs first; a false statement costs seconds to find by evaluation and hours by proof.
8. **Give reviewers the document, not a summary.**
9. **Record friction.** Keep `examples/<app>/FRICTION.md`: every time the framework, Lean or these instructions slowed you down, add a row (date, stage, what happened, what would have helped).

## Roles
Each role is a Claude Code subagent in `.claude/agents/` (`mil-spec-author`, `mil-spec-critic`, `mil-implementer`, `mil-prover`, `mil-auditor`). Write access is **enforced** by project hooks (`.claude/settings.json`): `tools/hooks/guard_role.py` lets each role write only its own area of `examples/<app>/` (spec, critic, impl, proofs, trust; `FRICTION.md` is shared), and `tools/hooks/guard_locked.py` blocks every agent, roles or not, from editing a file listed in a `spec.lock`. A blocked write is final: stop and report, never work around it. When one session plays every role instead, keep them separate in your head:
- **Spec author:** turns approved requirements into the model, layout, `pickRef` and theorem statements.
- **Spec critic:** tries to break the spec. Vacuous statements, missing cases, user data that imitates the format, bounds that are never stated. Writes wrong implementations the spec must reject.
- **Implementer:** writes the fast code, mirroring the reference function by function so the proof is a correspondence.
- **Prover:** proves the obligations. Uses `knowledge/LEMMAS.md` before writing new lemmas; uses `omega` for arithmetic.
- **Auditor:** runs `mil audit`, writes `TRUST.md`, refuses to call anything proven that is only tested.

## Commands
```
mil init <App> examples/<app>            # Stage 0: create the app from the template (a working counter)
mil review examples/<app>/mil.json       # Stage 2: SPEC_REVIEW.md for the user
mil freeze examples/<app>/mil.json <who> # Stage 2: after sign-off
mil check-lock examples/<app>/mil.json
mil contract examples/<app>/mil.json     # holes and obligations in the spec = mil.json's
mil judge examples/<app>/mil.json        # Stage 4: contract check, then the comparator's verdict
mil audit examples/<app>/mil.json        # Stage 6: everything (needs spec.lock; --allow-unfrozen for dev runs)
```
