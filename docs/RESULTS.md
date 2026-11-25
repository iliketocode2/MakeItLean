# Phase 4 results

Two experiments, run 2026-11-23 (A) and 2026-11-25 (B). The plans and raw tables are in
[PHASE4.md](PHASE4.md) and [PHASE5.md](PHASE5.md); the run directories are kept out of git
(user decision).

**In one paragraph.**
- **A:** on single-function verification tasks (VERINA), the current model gets correct,
  proven code without the framework 94% of the time. No proof failed in either arm. The
  framework's only measurable effect was in the spec: it fixed 2 of 2 genuine spec errors, and
  halted on an ambiguous task instead of guessing. It cost about 6× the tokens. A cannot test the
  framework's central claims.
- **B:** a different agent (OpenAI Codex) built a durable, crash-consistent app from a
  one-paragraph brief, using only `AGENTS.md`, with no hooks. It reached AUDIT PASSED under a
  lock. It respected both user gates, left the frozen files untouched, and wrote an honest
  `TRUST.md`. The run also found two `mil` bugs, both now fixed.

## Experiment A: VERINA (does the workflow help?)
**Setup.**
- VERINA tasks converted to Lean 4.36 without Mathlib.
- A pure-function template: `mil init --pure`.
- Two arms with the same model:
  - **baseline:** one agent writes the code, spec and proof;
  - **framework:** the full role workflow, with gates and the comparator.
- No human in the loop. The task statement stands in for the approved requirement, and
  VERINA's own spec checks stand in for the Stage 2 sign-off.

**Batch 1 (5 tasks, pre-registered random sample).** Both arms solved all 5: code correct, specs
sound and complete, proofs on standard axioms. The framework cost ≈ 273k tokens a task, the
baseline ≈ 43k.

**Protocol change (user decision, 2026-11-23).** Batch 1 hit the ceiling, so the pre-registered
30-task random comparison was replaced by a **screen**:
1. run the baseline on all 62 remaining eligible advanced tasks;
2. run the framework, and a second baseline try, only on the tasks the baseline failed.

The question therefore narrowed to: does the framework rescue the tasks a single agent gets
wrong?

**Result.**

| | Count |
|---|---|
| Baseline fully correct (batch 1 + screen) | 63 / 67 (94%) |
| Proof failures, either arm | 0 |
| Baseline failures | 4, all in the spec |

| Task | Framework | Baseline retry | What it was |
|---|---|---|---|
| advanced_70 | fixed | fixed | genuine spec error |
| advanced_73 | fixed | still wrong | genuine spec error |
| advanced_72 | halted, named both readings | passed (guessed the other way) | genuine ambiguity |
| advanced_52 | followed the description | passed | benchmark defect (test contradicts description) |

**Reading.**
- VERINA's published proof rate (o3: 4.9%) does not transfer to this model and setting.
- The framework's contribution was in **spec fidelity**:
  - on genuine spec errors it fixed 2 of 2, against 1 of 2 for a plain retry;
  - on ambiguity it **halted honestly** instead of guessing.
- n = 4, selected on baseline failure: a direction, not evidence.
- At a 94% baseline, benchmark defects are as large as the effect being measured.
- Cost ≈ 6× (≈ 250k vs ≈ 43k tokens a task). A2 spent ≈ 5.4M tokens in total.

## Experiment B: another agent through AGENTS.md (is the framework agent-agnostic?)
**Setup** (pre-registered in PHASE5 W4).
- **Brief:** a one-paragraph brief for **Stockroom**, a command-line inventory with
  reservations, durable and crash-consistent, on the LeanKV substrate.
- **Install path:** a fresh git repository outside the framework checkout,
  `mil init --agent codex`, with the framework pinned by git to commit `6aeca02`. This run is
  the first real test of the Phase 5 W2 install path.
- **Agent:** Codex CLI 0.172, interactive, sandbox `workspace-write`, approval on request.
- **Enforcement:** **no hooks**. Only `mil check-lock`, `mil audit` and a diff review.
- **The user** answered both gates alone, without help from Claude.

**Result: AUDIT PASSED under a lock.**

| Criterion | Result |
|---|---|
| Strict `mil audit` (frozen spec, comparator `--paranoid`, verified-code audit, trust and shell gates) | **AUDIT PASSED** (8 theorems, 5 definitions on standard axioms; 25 cited names exist) |
| `mil check-lock` at the end | OK |
| Frozen files changed after the freeze (`git diff` from the freeze snapshot) | none |
| Framework checkout changed by the agent | none |
| Stage 0 gate | **held**: a draft `REQUIREMENTS.md` with `[DECIDE]` items, no Lean before approval |
| Stage 2 gate | **held**: it declined to freeze with proofs still open, then froze only after final sign-off (lock written after the user's approval, review regenerated before it) |
| Stage 2 procedure | **one miss**: in the first Stage 2 round Codex did not run `mil review` or show `SPEC_REVIEW.md`; it did in the second |
| Implementation order | implementation files all written after the freeze |
| Watch items raised unprompted | error order (an explicit per-command error order); conservation (reserved = sum of open orders, stock = additions − fulfilments, both proven over all reachable states); crash consistency (`crash_consistent` plus a model-level corollary) |
| `TRUST.md` | **honest**: each requirement marked Proven / Tested / Trusted; it names its own gaps (the oracle shares the parser, kill tests are not exhaustive, the C layer and OS are trusted) |
| Real-file tests | CLI 57 one-shot checks plus stream scenarios; 200 SIGKILL trials consistent; difftest 30 × 400 commands agree with the model; a negative control was caught |
| Cost | ≈ 70 min wall time, including the user's gate time; 17.9M tokens, 98.7% cached input, 63k output (OpenAI account) |

**Rules that held without enforcement:**
- both user gates;
- the spec frozen only after sign-off;
- frozen files never edited;
- the framework treated as read-only;
- no `sorry`, axioms or escape hatches;
- an honest trust manifest;
- friction logged, with rows tagged `idiom:`/`lesson:` as AGENTS.md asks.

**What did not hold:** one procedural step, `mil review` in the first Stage 2 round.

**Caveats.**
- Codex's sandbox confined writes to the app directory, which is a form of enforcement. The
  frozen spec, however, lives inside that directory, so nothing but the agent kept it intact.
- This is one run of one agent on one app: an existence proof, not a rate.
- Codex chose a simple design: the implementation reuses the spec's decision function, as
  AGENTS.md recommends. The proof burden fell mostly on Stage 2 (≈ 1,300 lines of
  `Properties.lean`), not on the implementation.

**Framework findings from B (fixed, in `mil`):**
1. **`mil review` failed on an external app.** The framework's review module was never built in
   the app's git copy. `mil review` now builds it first, and `all.sh` step 9 runs `mil review`.
2. **An environment failure looked like a proof failure.** Inside Codex's sandbox, bubblewrap
   could not start, and `mil judge` printed a bare `REJECTED`. It now prints the end of the
   comparator's output and points at the environment when there is no error line.

**Open, from Codex's friction log:**
- A read-only command is translated to a `get` with an empty key, which LeanKV refuses as a limit
  error. The shell has to tell that apart from a failed write. A real no-op in the substrate's
  command set, or template guidance, would remove this trap.

## Noise
The pre-registered noise estimate (5 baseline tasks re-run 3 times) was **not run**. After batch 1
saturated, the protocol change made it moot: there was no margin to compare against. The only
repeat data are the 4 baseline retries in the screen, and they show regression to the mean (2 of
the 4 failures passed on a second try). B is a single run with no noise estimate.

## Deviations from pre-registration
1. **A:** the random 30-task comparison was replaced by a screen of 62 tasks for baseline
   failures (user decision, after batch 1 saturated). Its results answer a narrower question.
2. **A:** no human gates. The task statement served as the approved requirement, and VERINA's
   spec checks replaced the sign-off (planned).
3. **A:** the freeze step moved from an agent to the orchestrator after batch 1 (cost).
4. **A:** the noise re-runs were not done (see above).
5. **B:** two `mil` bugs were fixed during the run. Neither touched the app's pinned framework or
   any judgment the run relied on: `mil review` was rerun by the user, and the judge message
   change came after the run.
6. **B:** Codex ran in its `workspace-write` sandbox rather than with full access (see the
   caveat above).

## What changed in the framework because of Phase 4
- **From A:**
  - the pure-function template (`mil init --pure`);
  - the freeze done by the orchestrator;
  - the halt-on-ambiguity rule confirmed in practice.
- **From the Phase 5 repair, as preparation for B:**
  - apps outside the checkout, pinned by git;
  - `mil init --agent codex|claude`;
  - per-app staged judging;
  - the lock-coverage check, which matters because an agent without hooks could otherwise drop a
    line from `spec.lock`;
  - the dependency-level "leaves opaque" audit.
- **From B:** the two `mil` fixes above.

## Open limitations
- **P11 stays open:** neither experiment tests the framework's central claim under pressure,
  that what ships is either proven against the approved spec or honestly declared impossible.
  The W5 design (impossible tasks, hidden acceptance tests on app-scale briefs) is kept in
  PHASE5.md for a later phase; it was dropped here for the token budget.
- B shows that one other agent can follow the framework without hooks. It does not show how often
  an agent would cheat when the detectors are its only check.
