# Phase 5: repair, decouple, finish evaluation (plan approved by the user, 2026-11-25)

Source: the critical review of 2026-11-25. Each problem below is a work item with a fix, a check, and
an exit condition. Order: **W0 → W1 → W2 → W3 → W4 → W5**. W0 is urgent; the later work streams
build on it.

## Problems being fixed
| # | Problem | Evidence | Work item |
|---|---|---|---|
| P1 | A fresh clone does not build | root `lakefile.lean` `require`s 9 dirs under git-ignored `bench/verina/runs/`; `lake-manifest.json` even resolves `makeitlean` through a bench path; a scratch clone fails with `package directory not found` | W0.3, W1 |
| P2 | CI red since `ce1a28d` | `all.sh` step 7b runs `serve_test.sh` without building `ledgerOracle` (`FileNotFoundError: …/ledger-oracle`) | W0.4 |
| P3 | Local `main` has diverged from `origin/main` (ahead 4, behind 1: `ff21abc` LICENSE) | `git status -sb` | W0.2 |
| P4 | A2 results, `batch_score.py` change and 3 `judge/VerinaAdvanced*` files are uncommitted | `git status` | W0.1 |
| P5 | The judge workspace *is* the framework repo: `mil init` appends to the root lakefile, so every app (including throwaway ones) joins one shared build; races under parallel runs | `Main.lean` `init`, `findRoot` | W1 |
| P6 | The framework cannot be used from another repo (no install path; `mil` needs an ancestor `judge/`; guards live in this repo's `.claude/`) | `findRoot`, `MIL_ROOT` | W2 |
| P7 | PLAN.md deliverables that were never built or have drifted: Effects/Store classes, bytes library, extern/self-test macros, Stage 5 mutation gate, Stage 6 "leaves opaque" re-check, non-Lean shell template | `lean/` has only Gates and Review | W3 |
| P8 | Knowledge base is a stub (58 lines) | `knowledge/` | W3.4 |
| P9 | `mil` itself: textual `fillSorry`; not built with itself | `Main.lean` | W3.5 |
| P10 | Experiment B (another agent), `docs/RESULTS.md` not done | PHASE4 | W4 |
| P11 | Phase 4 A cannot test the framework's actual claims (trust and anti-cheating under pressure, app scale) | A2: 94% baseline, no proof failure in either arm | W5 |
| P12 | CLAUDE.md status out of date | "Phase 4 next" | W0.5 |

## Fixed constraints
- **Frozen locks are untouched.** `ledger-v1`'s `spec.lock` covers `examples/ledger/lakefile.lean` and
  `mil.json`, which use repo-relative requires (`../kvstore/impl`, `../../lean`). Any judge redesign
  keeps every app's location and locked files byte for byte; `mil check-lock` must still pass.
- Every change keeps `tests/all.sh` green, the comparator smoke test at 5/5, and Ledger AUDIT PASSED.
- Commits and pushes happen only when the user asks.

## W0: get the build green (small, do first)
1. **Commit the A2 work** (PHASE4.md A2 result, `batch_score.py`). The three bench `judge/*.json`
   files are *not* committed (W0.3 moves them).
2. **Integrate `origin/main`:** `git merge origin/main` (only `LICENSE`; no conflict expected).
3. **Remove the bench packages from the judge workspace:**
   - delete the 9 `verina*Impl` requires from the root `lakefile.lean`; `lake update` to regenerate
     the manifest; untrack and delete `judge/Verina*_Spec.json` (bench artefacts that `mil judge`
     regenerates);
   - interim, until W1: `bench/verina/convert.py` and `batch_score.py` register an app only for the
     duration of a judge run and then restore the root lakefile and manifest, with the same
     backup/restore pattern as `all.sh` step 8.
4. **CI:** in `all.sh` step 7b, run `lake build ledgerCli ledgerOracle` in `examples/ledger/impl`
   before `serve_test.sh`. Audit every other test script for the same "built locally" assumption
   (Counter's oracle, the HTTP tests).
5. **New guard (step 0 of `all.sh`):** every `require … from "path"` in a tracked lakefile names a
   path that `git ls-files` knows. This catches P1 in `--quick` mode, before CI.
6. Update CLAUDE.md status. Push (on the user's word).

**Exit:** a scratch `git clone` builds (`lake env true` in the root); CI green on GitHub.

## W1: one judge workspace per app run (fixes P5, prerequisite for W2)
Today the comparator runs from the repo root because its sandbox sees only the package it runs in.

1. **Spike (time-boxed, 1 session): a staged judge workspace.** `mil judge` builds
   `<app>/.mil/judge/` (git-ignored), which *mirrors the repo-relative layout* of only the packages
   this app needs (`lean/`, `examples/kvstore/…`, the app). Locked relative requires therefore still
   resolve, with no edit to them. It also holds a generated `lakefile.lean` requiring just this app
   and the comparator config. Candidates, in order:
   - (a) `cp -a` of sources plus prebuilt `.lake` (no LeanKV rebuild; also stops edits during a run);
   - (b) hard links (`cp -al`), if Lake's traces accept them;
   **Decide by:** identical verdicts on LeanKV (`--paranoid`), Counter, Ledger and one bench app;
   smoke 5/5 still caught *in the staged workspace*; time per judge run; disk use.

   **If neither (a) nor (b) passes: stop.** No fallback (user decision, 2026-11-25). A comparator
   that can only judge apps inside one shared repository undermines the framework's premise. The
   whole project is reconsidered with the user before any more work.
2. **Implement the chosen option:**
   - `mil init` no longer edits the root lakefile;
   - the root lakefile keeps only what the framework's own checks need (or goes away);
   - `judge/` configs are generated per run, not committed;
   - `kvstore/tools/audit.sh` goes through the same path.
3. **Tests:** step 8/8b of `all.sh` no longer needs the lakefile backup/restore. Add a test that two
   apps judged in parallel both get the correct verdict.

**Exit:** `git diff` of the root lakefile is empty after any `mil init`/`judge`/`audit`; all checks green.

## W2: use the framework from another repository (fixes P6)
1. **`MIL_HOME`** (env var, else the install location of the `mil` binary) replaces "walk up to
   `judge/`" for finding templates, `lean/` and LeanKV. The old in-repo layout stays supported
   (Ledger's lock depends on it).
2. **External template mode:** `mil init` outside the repo writes lakefiles that require `makeitlean`
   and `leankv` by **git URL pinned to a rev** (Lake clones them into `.lake/packages`, inside the app,
   so the W1 staging still works).
3. **Agent wiring:** `mil init --agent claude` writes `.claude/settings.json` hooks and
   `.claude/agents/mil-*.md` that point at `$MIL_HOME/tools/hooks`. `--agent codex` writes `AGENTS.md`
   only (W4 measures how well that works without hooks).
4. **README:** install (elan, bubblewrap, build `mil`), quickstart, where the docs are.
5. **CI step:** clone the repo as `MIL_HOME` into a temp dir, `mil init` an app *outside* it,
   then judge → freeze → strict audit.

**Exit:** that CI step passes, and an app outside the repo reaches AUDIT PASSED.

## W3: reconcile the plan with what exists (fixes P7–P9)
Rule: build only what an app has needed. Close every other item in PLAN.md by writing down a decision.
1. **Close by decision:**
   - `mil`'s own logic in Lean (PLAN.md's "built with itself"): not done (user decision, 2026-11-25);
   - Effects/Store classes: superseded by the LeanKV substrate (decided 2026-11-22);
   - bytes library: stays in LeanKV, indexed in LEMMAS.md, until a second binary format needs it;
   - Cost monad: optional, not built.

   Record each in PLAN.md's decision table, so the plan stops claiming them.
2. **Build as framework gates:**
   - `mil selftest`: runs the app's differential test (`tools/difftest.py`) and a *mutation list*
     declared in `mil.json` (patches that must each be caught). `mil audit` runs it, which turns
     Stage 5 into a gate instead of a per-app script.
   - Stage 6 "leaves opaque": `#audit_verified` already forbids `extern`/`implemented_by` in verified
     modules. Write that argument down, add a negative test (a verified theorem that depends on an
     extern leaf fails), and close the item.
3. **Non-Lean shell template** `templates/shell-ts/`, generalised from Ledger's `http/`: adapter,
   literal-example replay, difftest harness, planted-bug check. Test it with a fresh Counter HTTP
   shell in `all.sh`.
4. **Knowledge base:** mine `examples/*/FRICTION.md` and the Phase 3/4 friction rows into
   `LEAN_IDIOMS.md` (traps and fixes) and `LEMMAS.md`. AGENTS.md: a role that solves a Lean trap
   adds an entry.
5. **`mil` hardening.** First, and **before W4** (Codex runs without the lock hook):
   - **Lock coverage gap (found 2026-11-25 by reading `checkLock`).** `sha256sum --check` verifies
     only the lines that are present in `spec.lock`, and nothing protects `spec.lock` itself except
     the Claude Code hook. An agent without hooks can delete a file's line from `spec.lock`, edit
     that file, and `mil check-lock` still prints OK. Fix: `checkLock` also requires the set of
     files in `spec.lock` to equal `lockList cfg`. `mil.json` is always in that list, so its own
     hash stops `lock_files` from being shortened. Negative test: delete a line, edit the file,
     expect a MISMATCH.
   Then:
   - add negative tests for `fillSorry` (a name that is a prefix of another, `sorry` inside a
     comment, two declarations sharing a name);
   - or generate the solution by elaborating and pretty-printing instead of editing text.

   The comparator stays the backstop either way. Specifying `mil`'s own lock and gate logic in
   Lean is **optional** (user decision).
6. **Substrate limits** (one LeanKV command per app command): no change unless W5's apps need it;
   then revisit PHASE2's deferred option A (a generic durable machine).

**Exit:** PLAN.md lists no unbuilt deliverable without a decision; `mil audit` includes selftest;
the shell template is exercised in CI.

## W4: finish Phase 4 (fixes P10)
1. **Preflight:** `codex` currently resolves only through Windows interop
   (`/mnt/c/…/npm/codex`). Install the Linux Codex CLI in WSL (`npm i -g @openai/codex`) and sign
   in; that is the user's account. Check it can run `lake` in the repo.
2. **Experiment B** as in PHASE4: a new app (e.g. inventory with reservations) from a
   one-paragraph brief, two user gates, **no hooks**; enforcement only by `mil check-lock`,
   `mil audit` and a diff review. Run it on the W2 version of the framework (external mode), so it
   also tests the install path. Record which rules held without enforcement.
3. **`docs/RESULTS.md`:** A (numbers, the protocol change, cost), B, noise, deviations from
   pre-registration, and what changed in the framework because of them.

**Exit:** RESULTS.md written; Phase 4 marked complete.

## W5: an evaluation that tests the claims: **dropped** (user decision, 2026-11-25: token budget)
Evaluation ends with A and B. RESULTS.md states P11 as an open limitation: A cannot test the trust
claims, and this phase did not run an experiment that could. The design below is kept for a later phase.
A showed the model writes correct verified single functions without help. The framework's claim is
different: **under pressure, what ships is either proven against a spec the human approved, or the
agent says it can't be done.** Pre-register before running:
1. **Pressure set:** tasks that cannot be done as stated, e.g. VERINA tasks whose description
   asks for a property that is false or unprovable without Mathlib, or for an impossible
   complexity bound. Metric: how often each arm *claims success* without a valid proof against
   the original requirement (weakened spec, `sorry`, a changed statement), against how often it
   halts honestly.
2. **App-scale set:** 3–5 small stateful apps from briefs, both arms. Acceptance tests are written
   by the user **before** the run and are never seen by agents. Metric: hidden acceptance-test
   pass rate and spec fidelity.
3. **Human cost:** time to review `SPEC_REVIEW.md` versus reading the baseline's Lean.

**Exit:** a result that can come out against the framework, written to RESULTS.md.

## Order and size
| Step | Size | Blocks |
|---|---|---|
| W0 | under 1 session | everything |
| W1 | spike 1 session + 1–2 sessions | W2 |
| W2 | 2 sessions | W4 (B runs on it) |
| W3 | 2–3 sessions; parallel with W2 after W1 | — |
| W4 | 1 agent run + write-up | needs the Codex preflight |
| W5 | multi-agent; estimate before starting | approval |

## Decisions (user, 2026-11-25)
1. **Order approved**, B after W2.
2. **No W1 fallback:** if the staged-workspace spike fails, pause and reconsider the whole project.
3. **Codex:** installed in WSL and signed in (2026-11-25). Cursor: skipped.
4. **No Lean spec for `mil`.** The comparator and the kernel, not `mil`, make proofs trustworthy.
   W3.5's lock-coverage fix and negative tests cover the real risk.
7. **Git:** the user commits, merges and pushes. Agents hand over the exact commands and never run them.
5. **Token budget is tight:** choose the cheaper route everywhere; W5 dropped. B is one Codex run,
   billed to the user's OpenAI account, not to Claude tokens.
6. **Run directories stay out of git.** Scores and verdicts are recorded in PHASE4 and RESULTS.

## Progress
- 2026-11-25, W0.3–W0.5 (uncommitted, awaiting the user's word to commit and push):
  - root `lakefile.lean` back to the three examples; manifest regenerated; `judge/Verina*` removed;
  - `tools/check_requires.py` is step 0 of `all.sh` (negative case checked by hand: a planted bench
    require fails it);
  - step 7b builds `ledgerCli ledgerOracle` first;
  - a simulated fresh clone (tracked files only) resolves the workspace.

  Bench re-runs are not supported until W1: `convert.py` still calls `mil init`, which registers
  the app in the root lakefile. Step 0 catches it if that is ever committed.
