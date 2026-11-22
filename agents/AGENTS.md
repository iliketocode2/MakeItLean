# MakeItLean — instructions for coding agents

You are building an application **spec-first in Lean 4**. The code that runs must be *proven* against a spec the user approved and froze, or differentially *tested* against it. An external judge (`lake comparator`) checks the proofs; you cannot talk your way past it. Read this whole file before starting, then [knowledge/LEAN_IDIOMS.md](../knowledge/LEAN_IDIOMS.md) and [knowledge/LEMMAS.md](../knowledge/LEMMAS.md).

## Environment
- Linux/WSL. Lean `v4.36.0` (pinned in every `lean-toolchain`). Build with `lake build`. No Mathlib.
- `mil` is the framework CLI: `~/MakeItLean/cli/.lake/build/bin/mil` (build it with `cd cli && lake build` if missing).
- The repository root is the **judge workspace** (`lakefile.lean`, `judge/`). Apps live in `examples/<app>/`.

## The pattern: an app on the LeanKV substrate
Durable apps keep their state in **LeanKV**, a proven ordered key-value store (`examples/kvstore/`). Each app command becomes **exactly one KV command** (a read, or one atomic `put`/`delete`/`batch`), chosen by a function `pick` from the current store contents. LeanKV's theorem `substrate_crash_consistent` then gives the app durability and crash consistency **for free**: after any crash, the store holds exactly the acknowledged commands, plus possibly the one in flight, applied in full. The app proves only that `pick` implements its own spec.

The worked example is **`examples/counter/`**. Read it end to end before writing anything; your app has the same shape.

| File | What goes in it |
|---|---|
| `REQUIREMENTS.md` | Stage 0: plain English, IDs R1…, examples, non-goals, storage layout. |
| `<App>/Spec/Model.lean` | The reference model: commands (generic in the byte type `β`, with a `map`), answers, the state (a function or a simple list), `cstep : State → Cmd Bytes → State × Answer`. Then the **storage layout**: how state maps to KV keys and values, `dec : Store → State` (what a KV store stands for), the value codecs, and the reference translation `pickRef : Store → Cmd Bytes → LeanKV Cmd Bytes`. Then the **Stage 2 theorems**: codec round trips and `pickRef_refines` (on every well-formed store, running `pickRef`'s KV command changes `dec` exactly as `cstep` does). |
| `<App>/Spec/Contract.lean` | **Only** the implementation hole(s) and their obligations. Keep holes in this separate file. `def Impl.pick : Tree → Cmd ByteArray → LeanKV.Spec.Cmd ByteArray := sorry` and `theorem impl_pick_ok … : (Impl.pick t c).map toBytes = pickRef t.toList (c.map toBytes) := sorry`. |
| `<App>/Spec.lean` | Imports plus the three gates (`#assert_english_docs`, `#assert_holes_only_in_theorems`, `#assert_spec_axioms`). |
| `impl/<App>Impl/Core.lean` | The implementation of `pick` on the in-memory `Tree`, reading it with `LeanKV.Core.lookup` (proven equal to the reference lookup). |
| `impl/<App>Impl/Proofs.lean` | The proof of the obligation (see `CounterImpl.pick_ok`: `toList_lookup` bridges `Core.lookup` to the spec). |
| `impl/<App>Impl/Shell.lean` | The CLI: open the store on real files (`LeanKV.Shell.lkvOpen`, `RealM`), run `LeanKV.Core.execPick`, print answers. Trusted, not verified: keep it thin. |
| `mil.json` | Which files hold holes, how each hole and obligation is filled, which files the lock covers. |

**Import `LeanKVSol.Base.*`** (LeanKV's hole-free library spec) for LeanKV types and lemmas, **never `LeanKV.Spec.*`**. The latter clashes with LeanKV's core.

## Workflow: stages and gates
Never skip a gate. Stages 0 and 2 end with **the user's explicit approval**. Ask, and wait.

| # | Stage | You do | Gate |
|---|---|---|---|
| 0 | Requirements | `mil init <App> examples/<app>`; write `REQUIREMENTS.md`. Mark open questions **[DECIDE]** and ask the user. | **User approves `REQUIREMENTS.md`.** Do not write Lean before this. |
| 1 | Spec | Write `Spec/Model.lean` and `Spec/Contract.lean`, replacing the counter example. Every declaration carries `/-- English: … -/`. Statements of Stage 2 theorems may be `sorry` for now. | `lake build` in the spec package: all three gates pass. |
| 2 | Validate and freeze | Prove every spec theorem that does **not** name a hole (codecs, refinement). Add `#guard` examples from the requirements. Act as **spec critic**: try wrong implementations and check the spec rejects them. Run `mil review examples/<app>/mil.json`, show the user `SPEC_REVIEW.md`. | Spec-axiom gate: only obligations are open. **User signs off**, then `mil freeze examples/<app>/mil.json <user>`. After this, **never edit the files in `spec.lock`**; spec changes go back to the user for a new sign-off. |
| 3 | Implement | `impl/<App>Impl/Core.lean`. Test it against the spec by evaluation before proving (`#guard` over random commands). | `lake build` in `impl/`. |
| 4 | Prove | `impl/<App>Impl/Proofs.lean`; fill `mil.json`'s `holes` and `obligations`. | `mil judge examples/<app>/mil.json` prints **ACCEPTED**. |
| 5 | Boundary | The CLI; real-file tests; tests at every size limit in the requirements (proofs do not bound stack or memory). | Tests pass. |
| 6 | Audit | `TRUST.md`: each requirement proven / tested / trusted, citing theorem names. | `mil audit examples/<app>/mil.json` prints **AUDIT PASSED**. |

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
In one session you play all five; keep them separate in your head.
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
mil judge examples/<app>/mil.json        # Stage 4: the comparator's verdict
mil audit examples/<app>/mil.json        # Stage 6: everything
```
