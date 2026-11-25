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
- **Converter, done:** `bench/verina/convert.py framework|baseline TASK OUT`. Framework: a
  `mil init --pure` app with the description and signature as `REQUIREMENTS.md` (status: approved by
  the benchmark protocol; the hard stops stated), the contract generated from the signature, and
  the precondition, postcondition, function and proof left as marked stubs for the roles.
  Baseline: one `Solution.lean` in VERINA's layout with the same requirements. Neither arm gets
  the reference or the tests; signature text is checked against a whitelist before any Lean is
  generated from it. Run directories live in `bench/verina/runs/` (git-ignored).
- **Read guard, done:** `tools/hooks/guard_read.py`: any subagent is blocked from reading,
  searching, listing or running a command on `~/bench` (the dataset), and from looking VERINA up
  on the web; the main session (the scorer's side) is not. Verified live and in `test_guards.py`.
- **Sample, fixed before any run:** `bench/verina/sample.json`: seed 20261123, 17 basic + 13
  advanced from the eligible pool. Timing tasks drawn from outside it: `verina_basic_44`
  (used) and `verina_advanced_3` (spare).
- **Framework fixes found by the timing run:** (1) the role guard knew apps only under
  `examples/`, so every role was blocked in `bench/` (it now finds an app by its `mil.json`; the
  shell parser now follows `VAR=…` assignments and `$HOME`, and skips unknown variables);
  (2) `#assert_spec_axioms` ignored spec *definitions*, so a precondition or postcondition left as
  `sorry` passed the gates (it now fails them; negative test); (3) the pure template's generated
  solution was a default build target, so `lake build` failed during Stage 3 (no longer default).

### A1 timing run (2026-11-23): `verina_basic_44`, outside the sample
| Arm / role | Tokens | Tool calls | Wall time | Result |
|---|---|---|---|---|
| Baseline (one agent) | 41,797 | 3 | 24 s | builds; standard axioms only; 28/28 checks pass |
| Spec author | 49,814 | 5 | 76 s | gates pass; 26 worked examples (run resumed once after a usage limit) |
| Spec critic | 52,787 | 6 | 57 s | 15 planted wrong implementations, all rejected; no gap |
| (orchestrator) freeze | — | — | — | signed `benchmark-protocol-no-user-signoff` |
| Implementer | 58,595 | 9 | 62 s | tested by evaluation on 400 arrays |
| Prover | 56,014 | 5 | 28 s | `mil judge` ACCEPTED (re-run by the orchestrator) |
| **Framework total** | **217,210** | 25 | 223 s | 28/28 checks pass |

Not counted above (friction): the first spec-author attempt, blocked by the guard bug, 59,715
tokens and 61 s. Orchestrator tokens (relaying, verifying, scoring) are not in the subagent counts.

**Reading.** On an easy task both arms are fully correct, so there is no signal about quality yet:
that needs harder tasks. The framework costs about **5× the tokens and 9× the wall time** of the
baseline here. Each agent carries roughly 40k tokens of fixed context (system prompt, AGENTS.md),
so a four-role run is dominated by that fixed cost on small tasks.

### A2 batch 1 (2026-11-23): a ceiling
Tasks: `verina_advanced_12`, `verina_advanced_15`, `verina_basic_101`, `verina_basic_108`,
`verina_basic_12` (the first 2 advanced and 3 basic of the fixed sample). One workflow, 30 agents,
no errors, no halts. Scored by `bench/verina/batch_score.py` from the main session.

| Task | Framework | Baseline |
|---|---|---|
| advanced_12 | lock ok, ACCEPTED, all 41 checks pass; 286,894 tokens | proof ok, all 41 pass; 44,025 |
| advanced_15 | lock ok, ACCEPTED, all 28 pass; 281,949 | proof ok, all 28 pass; 42,729 |
| basic_101 | lock ok, ACCEPTED, all 30 pass; 251,534 | proof ok, all 30 pass; 41,054 |
| basic_108 | lock ok, ACCEPTED, all 30 pass; 277,187 | proof ok, all 30 pass; 46,969 |
| basic_12 | lock ok, ACCEPTED, all 30 pass; 266,671 | proof ok, all 30 pass; 41,427 |

- **Quality: no difference.** Both arms solved every task: code correct, specs sound and
  complete on every test, proofs on the standard axioms only. The two arms' postconditions are
  real declarative specs (not mirrors of the code) and nearly identical in content.
- **Cost:** framework ≈ 273k tokens a task (of which ≈ 39k is the freeze step, a fixed-context
  agent that runs one command; it can be done by the orchestrator), baseline ≈ 43k: **≈ 6×**.
  Advanced tasks cost about the same as basic ones, well under the 330–550k estimate.
- **Reading:** VERINA's published proof rate (o3: 4.9%) does not transfer to the current model on
  these converted tasks (Lean 4.36, core library, decidable specs). With both arms at 100%, the
  rest of the 30-task sample is unlikely to separate them.

### A2 protocol change (user decision, 2026-11-23): screen for hard tasks
Because batch 1 saturated, the pre-registered random 30-task comparison is replaced by a
**screen**. The question changes from "does the framework do better on a random sample?" to
"**does the framework rescue the tasks a single agent gets wrong?**", and results must be read as
answering that narrower question (selection on baseline failure; regression to the mean is
possible, so a rescued task is re-run with the baseline too).
1. Run the baseline alone on every eligible advanced task not yet run (62 tasks).
2. A task counts as a **baseline failure** if the proof is not accepted, the code fails a test, or
   the spec fails a soundness or completeness check (`batch_score.py`'s criteria).
3. If there are failures: run the framework on exactly those tasks, and the baseline once more on
   each (to separate "the framework helped" from "a second try helped").
4. If there are none: the ceiling is confirmed for this model on VERINA; record a null result and
   go to Experiment B.
The freeze step is done by the orchestrator from now on (it cost a fixed-context agent per task).

### A2 result (2026-11-23)
**Screen** (`bench/verina/screen_score.py`): the single-agent baseline on the 62 remaining
eligible advanced tasks. 62 done, 0 halted (46 were cut by the usage limit and re-run from fresh
workspaces). **58 / 62 fully correct**: code right, spec sound and complete on every test, proof on
the standard axioms. 4 baseline failures, all in the *spec*, none in a proof:

| Task | Baseline (1st) | Framework | Baseline retry | What it really was |
|---|---|---|---|---|
| advanced_52 | precondition rejects a test input | same | passes | **benchmark defect:** the failing test has `k = 0`; the description says k is positive. The framework followed the description. |
| advanced_70 | precondition too weak | **fixed** | fixed | genuine spec error |
| advanced_72 | answers 2 for `n = 0` (VERINA expects 0) | **halted** on the ambiguity, as the protocol requires | passes (guessed the other way) | **genuine ambiguity:** every prime divides 0; the description does not settle it |
| advanced_73 | precondition too weak | **fixed** | still too weak | genuine spec error |

**Reading.**
1. **Ceiling.** With batch 1, the baseline is fully correct on 63 of 67 advanced and basic tasks
   (94%); VERINA's published proof rate for o3 (4.9%) does not transfer to this model in this
   setting. No proof failed in either arm, ever.
2. **Where the framework differs, it is in the spec.** On the 2 genuine spec errors, the framework
   fixed **2 / 2**, a plain retry fixed **1 / 2**. On the ambiguous task the framework **halted
   and named both readings** instead of guessing (the baseline's two tries guessed opposite ways).
   On the defective test it followed the description over the test. All of this is n = 4: a
   direction, not evidence; selection on baseline failure means regression to the mean is
   expected (the retry shows it).
3. **Cost.** The framework costs about **6×** the tokens of a single agent per task (≈ 250k vs
   ≈ 43k; the freeze agent alone is ≈ 39k and could be removed).
4. **Benchmark quality matters at this level.** 2 of the 4 "failures" are VERINA's: a test that
   contradicts its description, and an underspecified edge case. At a 94% baseline, benchmark
   noise is the same size as the effect being measured.

**Tokens spent on A2:** batch 1 1.55M, screen 2.80M (including the interrupted part), rescue
1.01M: **≈ 5.4M** of the approved 11–17M.

**Conclusion for experiment A.** On VERINA, the current model does not need the framework to get
correct verified code; the framework's measurable contribution is in spec fidelity (2/2 vs 1/2) and
in halting on ambiguity rather than guessing, at about 6× the cost. A benchmark that separates the
arms needs harder tasks (whole applications, stateful or multi-function specs, as in Phases 2–3)
rather than single functions.

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
