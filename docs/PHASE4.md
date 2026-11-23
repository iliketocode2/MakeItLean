# Phase 4: evaluation (plan approved by the user, 2026-11-23)

PLAN.md's Phase 4: measure on a subset of VERINA or FVAPPS; try other agents through `AGENTS.md`;
optional prover back ends (Leanstral, Aristotle). This plan turns that into experiments with a
question, a baseline, a metric and a pass/fail reading, so the result says something whichever
way it comes out.

## The questions
1. **Does the workflow help?** On small, externally defined verification tasks, does an agent
   following MakeItLean (requirements → spec with gates and a spec critic → implementation →
   comparator-judged proof) produce *correct code with sound specs and real proofs* more often
   than the same model given the same task without the framework?
2. **Is the framework agent-agnostic?** Can an agent other than Claude Code follow `AGENTS.md`
   to a passing `mil audit`, without the Claude-specific hooks?
3. **Can a stronger prover back end close the proof gap?** Optional, only if 1 shows proofs are
   the bottleneck (the literature says they are: VERINA o3 4.9% proofs; RESEARCH.md §2.1).

## Experiment A: a VERINA subset (recommended over FVAPPS)
**Why VERINA first.** Its three tasks match our stages: code generation (implementer), spec
generation (spec author) and proof generation (prover), from a natural-language description, a
signature and tests, with its own judgement of spec soundness and completeness. FVAPPS gives the
theorems and asks for proofs only (4,715 tasks), so it measures the prover role alone; it is the
better choice for Experiment C, not for the workflow as a whole.

**Step A0: feasibility spike (do first; 1 session).** Before committing to numbers:
- fetch the dataset into its own directory (untrusted data, per the environment rules); record its
  licence, size, Lean version and whether tasks need Mathlib;
- port **5 tasks** to Lean 4.36 without Mathlib (our pin and rule) and run them through `mil`;
- decide the harness: how a task becomes a `mil init` app (most VERINA tasks are a pure function,
  so the LeanKV substrate is not used: the template needs a **pure-function variant**: spec with
  a reference function or postcondition, one hole for the implementation, one obligation);
- **stop and report** if Mathlib is unavoidable or porting costs more than ~15 minutes a task.

**Step A1: the pure-function template** (framework work, before any measurement): `mil init
--pure`, a spec with `Spec/Model.lean` (the postcondition or reference), `Contract.lean` (the hole
and its obligation), `Properties.lean` (the task's tests as `#guard`), no substrate, no shell.
Same gates, same comparator, same audit.

**Step A2: the runs.**
- **Subset:** 30 tasks, stratified (VERINA's basic and advanced splits), chosen by a fixed random
  seed before any run, recorded in the repo.
- **Arms**, same model and the same per-task budget (time and tokens):
  - *baseline*: one agent, the task as given, plain Lean, asked for code, spec and proof;
  - *framework*: the MakeItLean workflow with roles (spec author → spec critic → implementer →
    prover), gates and the comparator, run as a workflow over the 30 tasks.
- **No human in the loop for routine progress.** Benchmarks have no user to approve Stage 0/2.
  The task statement is the approved requirement; the spec sign-off is replaced by VERINA's own
  spec evaluation after the run. This is a deviation from the framework's normal use, and every
  task's `TRUST.md` and `docs/RESULTS.md` must say so.
- **Hard stops remain.** An agent still **halts and reports instead of guessing** when a task needs
  a forbidden dependency (Mathlib, a custom axiom, `native_decide`), when the task statement is
  ambiguous in a way the tests do not settle, or when the harness or environment is broken (a
  build that fails before any agent edit, a missing tool, a guard blocking a legitimate write).
  A halted task is recorded as *halted, with the reason*, never silently counted as a failure or
  a pass, and the orchestrator brings it to the user.
- **Metrics per task:** code correct (VERINA tests); spec sound and complete (VERINA's checks);
  proof accepted (our comparator, standard axioms only); cheating caught (gate or comparator
  rejections, by kind); wall time and tokens.
- **Reading:** the framework helps if it raises *spec soundness* or *accepted proofs* by a margin
  larger than run-to-run noise (estimate noise by re-running 5 baseline tasks 3 times). If it only
  costs more, say so plainly.

### A0 result (2026-11-23): GO
VERINA at commit `66b3ce5` (Apache-2.0), cloned to `~/bench/verina` (outside the repository; not
committed). 189 tasks (108 basic, 81 advanced). Each task is one Lean file with marked sections
(imports, helpers, precondition, code, postcondition, proof), a description, tests
(`input`, `expected`, `unexpected` outputs) and `reject_inputs` for preconditions. VERINA itself
pins Lean 4.18 with Mathlib, but the Mathlib import belongs to the *reference solution*, not to the
task.

`bench/verina/port_check.py` rebuilt every task on **Lean 4.36 without Mathlib**:
- **Reference specs** (helpers, precondition, postcondition; code and proof left as `sorry`):
  **181 / 189 build** (107/108 basic, 74/81 advanced). Of the 8 that fail, **2 need Mathlib**
  (`Nat.Prime`, `List.sublists`): excluded. **5 are 4.18→4.36 drift** (`String.data` is gone; one
  field-notation inference): a mechanical fix (`.data` → `.toList`). **1** hits a `simp` recursion
  limit under 4.36: excluded unless a one-line fix is obvious.
- **Full reference solutions** build in 122 / 189, mostly because reference *proofs* use Mathlib
  lemmas. This does not matter: the agents write their own code and proofs.

Porting cost is therefore near zero and automatic (a converter, not hand work), so the "15
minutes a task" stop does not apply. Consequences for A1–A2:
- **Eligible pool:** the 181 tasks whose specs build (after the 5 mechanical fixes, up to 186); the
  30-task subset is drawn from it with a fixed seed.
- **Spec evaluation:** VERINA's own rule, rebuilt in our harness: a generated postcondition is
  *sound* if it accepts every `expected` output and *complete* if it rejects every `unexpected`
  one (preconditions likewise against `reject_inputs`). Checked by `decide` where the proposition
  is decidable; VERINA falls back to Plausible (random testing; a separate library, not Mathlib).
  Whether to add Plausible is an A1 decision.
- **Converter:** a VERINA task becomes a `mil init --pure` app: the description and tests are
  the requirements, the reference spec is kept aside for evaluation only (never shown to the
  agents), and the tests become `#guard` lines.

### A1 progress (2026-11-23)
- **Decision (user):** no Plausible; `decide` only, and unsettled checks are counted, never scored.
- **Fairness decision:** neither arm sees VERINA's `test.json`; both get the description and the
  signature. The tests are used only for scoring (the framework's spec author writes its own
  worked examples from the description).
- **Pure-function template, done:** `templates/pure/` and `mil init --pure` (one function, a
  VERINA-shaped precondition and postcondition, one hole, one obligation; no substrate, no shell;
  `MIL_ROOT` makes it work at any depth). `mil audit` skips the shell gate for `"kind": "pure"`. A
  fresh pure app passes init → judge → freeze → strict audit; this is step 8b of `tests/all.sh`.
- **Scorer, done and validated:** `bench/verina/score.py` checks code correctness, postcondition
  soundness and completeness, and precondition soundness and completeness against a task's tests
  with `decide`. Values VERINA stores as Lean text are accepted only as plain literal syntax
  (whitelist; they are untrusted data). **Validated on VERINA's own references**
  (`validate_scorer.py`): 0 failures, 0 errors over 152 + tasks, every check either passes or is
  reported unsettled.
- **Eligible pool, fixed:** `bench/verina/eligible.json`: **152 tasks (88 basic, 64 advanced)**
  whose reference spec builds on 4.36 without Mathlib and whose every spec check `decide` settles
  (so every score of an agent's spec is definite). `decide` fully settles the reference
  postcondition in 109 / 122 fully built references, which is why Plausible is not needed.
- **Still to do in A1:** the converter (task → `mil init --pure` app: description and signature as
  the requirements, contract generated from the signature, precondition and postcondition left to
  the spec author; the reference held out), a **read guard** so role agents cannot open
  `~/bench/verina` (it holds the reference solutions and tests), and the one-task timing run per arm.

## Experiment B: another agent through AGENTS.md
- **Task:** the same as Phase 2's exit test (a fresh app from a one-paragraph brief, two user
  gates), with a new small app so no agent has seen the answer, e.g. an inventory with
  reservations, on the LeanKV substrate.
- **Agents:** OpenAI Codex CLI (scriptable, reads `AGENTS.md` natively). Cursor only if you want
  a manual run: it is an IDE and not scriptable here.
- **Without hooks:** Claude Code's role and lock guards do not exist for other agents. Enforcement
  falls back to the detectors: `mil check-lock`, `mil audit`, and a diff review. That is itself a
  finding: record which rules held without enforcement.
- **Reading:** reaches AUDIT PASSED under a lock (yes/no), gates respected, friction rows, and the
  same scoring as Phase 2 (watch items raised unprompted, honest TRUST.md).

## Experiment C (optional): prover back ends
Only if A shows proofs are the bottleneck.
- **Leanstral** (open weights, self-hosted): needs a GPU; check what the machine has first.
- **Aristotle** (Harmonic, commercial API): sends task code to an outside service, so it needs
  your explicit consent and an account; measure on the A subset's failed proofs (and FVAPPS
  if wanted), counting comparator-accepted proofs and disproofs of wrong specs.

## Order and size
1. A0 spike (go / no-go on VERINA). 2. A1 pure-function template (+ a CI check that a fresh
`--pure` app passes). 3. A2 runs. 4. B. 5. C if warranted. 6. `docs/RESULTS.md`: numbers,
noise, deviations, and what changes in the framework because of them.

Rough cost: A2 is the large item (2 arms × 30 tasks, plus 15 noise re-runs), run as a workflow;
B is one Phase-2-sized run per agent. I will give a token and time estimate after A0, when task
sizes are known, before starting A2.

## Decisions needed
1. **Benchmark:** VERINA for A (recommended), FVAPPS reserved for C; or FVAPPS for both.
2. **Subset size:** 30 tasks (recommended) or another number, given cost.
3. **Baseline:** same model, no framework, same budget (recommended).
4. **Other agents:** is the Codex CLI installed and signed in here? Cursor (manual) or skip?
5. **Prover back ends:** defer C until after A (recommended); Aristotle only with your consent to
   send code to an outside service.
6. **Multi-agent runs:** A2 and B spawn many agents; approve running them as workflows, with the
   cost estimate after A0.
