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
   **Draft run protocol (for the user's approval, 2026-11-26):**
   - **Brief (draft):**
     > Build **Stockroom**, a command-line inventory with reservations. It stores its state on
     > disk and survives crashes. Items have a name and a whole-number stock. A user can add stock,
     > reserve a quantity of an item for an order, release a reservation, fulfil it (stock leaves
     > for good), and look up an item's available quantity (stock minus reservations). Every
     > operation is all-or-nothing and says why when it refuses (unknown item, unknown order, not
     > enough available, a quantity of zero). Available stock never goes negative. After a crash,
     > the inventory shows exactly the operations it had acknowledged, possibly plus the one in
     > progress. Work out the exact requirements with me before you write any Lean.
   - **Setup:** a fresh git repository outside the checkout,
     `mil init --agent codex Stockroom stockroom`. Commit and push the framework first, since the
     app pins `HEAD`.
   - **Run:** start `codex` (interactive) in `stockroom/`, and paste the brief. Codex stops at
     Stage 0 (requirements) and Stage 2 (spec review); the user answers it directly, with no help
     from Claude.
   - **Scoring (as in Phase 2):**
     - AUDIT PASSED under a lock;
     - `mil check-lock` clean at the end, and `git diff` of the frozen files since the freeze is
       empty;
     - gates respected;
     - watch items raised unprompted: error order, conservation of reserved plus available,
       crash consistency;
     - an honest `TRUST.md`.

     Record every rule that held without hooks, and every one that did not.
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
- 2026-11-25, W0 committed by the user (`c72d89f`, merge `a57a6b4`); **CI green**.
- 2026-11-25, **W1 spike: PASSED with option (a), copy.** Staging script (scratchpad, not in the
  repo): copy only the app's packages with `cp -a` (sources + prebuilt `.lake`) to a directory
  **outside the repository**, at their repo-relative paths; generate a lakefile with one `require`;
  `lake update`; build; `lake comparator`. Locked lakefiles resolve unchanged; the generated
  manifest holds only relative paths.

  | App | Verdict (`--paranoid`, 6 kernels) | Stage | Build + judge | Size |
  |---|---|---|---|---|
  | LeanKV | ACCEPTED | 1.7 s | 51.9 s | 56 MB |
  | Ledger | ACCEPTED | 2.0 s | 22.6 s | 79 MB |
  | Counter | ACCEPTED | 1.6 s | 22.5 s | 74 MB |
  | verina_basic_12 (bench, pure) | ACCEPTED | 1.0 s | 17.6 s | 4.9 MB |

  The builds replay from the copied `.lake` (Counter: 0.5 s, nothing recompiled). The verdicts
  match the in-repo ones (`all.sh` steps 4–6; PHASE4 for the bench app).
  - **The judge reads the staged copy:** in staged Counter, a `sorry`, a custom axiom and a
    weakened statement were each REJECTED (`sorryAx`, `Counter.Spec.cheat`, "statement do not
    match"); the honest solution was ACCEPTED after restoring it.
  - **The smoke test passes outside the repository:** `tests/comparator-smoke` copied to a scratch
    directory, 5/5.
  - **Option (b), hard links, not pursued:** copying already takes about 2 s. With hard links, Lake's
    writes into the staged `.lake` could go through the links into the repository's build outputs.
  - Not yet shown: two parallel judge runs (W1.3's test). The staged directories share nothing, so
    no interference is expected.
- 2026-11-25, **W1.2–W1.3 done: the staged judge is in `mil`.**
  - **`mil judge`** builds the app and its solution in place. It then copies the app's path
    packages, read from the impl's `lake-manifest.json` (outermost packages only), into a `mktemp`
    directory, at their paths relative to their common ancestor. There it writes a one-require
    lakefile and `judge.json`, runs `lake update`, builds the challenge and solution (replayed), runs
    `lake comparator`, and deletes the directory (`MIL_KEEP_JUDGE=1` keeps it).
    - A git dependency is refused with a clear message (W2).
    - **`mil comparator [--paranoid] <impl> <config>`** does the same for a package with its own
      config; LeanKV's `judge.sh` uses it.
  - **`mil init` registers nothing.** The root `lakefile.lean`, `lake-manifest.json` and `judge/`
    are deleted.
  - **Repository marker changed.** `mil` and both guard hooks now find the checkout by
    `lean/MakeItLean/Gates.lean` (before: `judge/` + root lakefile). Without this the guards would
    have found no repository, and could have stopped protecting frozen files; test_guards 104/104.
  - **`all.sh`:** step 8's lakefile backup/restore is gone. New step 8c:
    - a planted `sorry` in a fresh pure app's `fill.json` is REJECTED (`sorryAx`) through the
      staged judge;
    - Counter and Ledger judged in parallel are both ACCEPTED;
    - no `lakefile.lean`, `lake-manifest.json` or `judge/` appears at the root.
  - **Two bugs found by the suite, fixed:**
    1. a package that *is* the common ancestor (LeanKV: `impl/` and its parent) got an empty
       relative path. Fix: go one level up. The spike missed this because it listed the packages
       by hand.
    2. the audit's verified-code check needs the solution built in the app, which the old root
       build did as a side effect. Fix: `mil judge` builds the solution module in place.
  - Full `tests/all.sh`: ALL CHECKS PASSED; no `mil-judge-*` directories left in `/tmp`.

  **W1 exit met.** Next: W2.
- 2026-11-25/26, **W2 done (the user was away; nothing committed).**
  - **`MIL_HOME`:** the env var, else the checkout `mil` was built in (from `IO.appPath`), else
    the nearest enclosing checkout.
  - **`mil init` outside the checkout** rewrites the templates' `"MIL_ROOT/<sub>"` requires to
    `git "<url>" @ "<commit>" / "<sub>"`.
    - The URL is `origin` and the commit is `HEAD`; `MIL_GIT_URL`/`MIL_GIT_REV` override them.
    - It warns if the checkout has uncommitted changes, or if the commit is on no remote branch.
    - The app template now uses `MIL_ROOT` too (it hardcoded `../kvstore/impl`, so it worked
      only directly under `examples/`). Its `test.sh` reaches `difftest.py` via `MIL_TOOLS`.
  - **One clone per app.** A spec package and its `impl/` are two Lake workspaces. With git
    dependencies each cloned the framework separately, and the audit failed with "unknown module
    prefix 'MakeItLean'". The templates' `impl/lakefile.lean` now sets
    `packagesDir := "../.lake/packages"`. The staged judge reads `packagesDir` from the impl
    manifest and copies git packages with the app.
  - **`mil init --agent claude|codex`** (external apps only).
    - Both write a preamble that maps the docs' repository paths onto `MIL_HOME` and the app.
    - codex: `AGENTS.md`.
    - claude: `CLAUDE.md`, `.claude/agents/mil-*.md`, and `.claude/settings.json` with the lock and
      role guards run from `MIL_HOME`.
  - **Guards outside the checkout.** `repo_root` is the nearest framework checkout or git
    repository, else the app directory. `guard_role.app_root` accepts the root itself as the app.
    14 new external cases (a git repo and a no-git directory); test_guards 118/118 at that point.
  - **Measured.** Pure app: build 9 s, judge 17 s, AUDIT PASSED. Substrate app (LeanKV fetched by
    git and built from scratch): spec 10 s, judge 39 s, CLI 9/9, kill test consistent, difftest
    6,000 commands agree, AUDIT PASSED in 52 s.
  - **`all.sh` step 9:** both kinds of external app go from init to strict audit, with the
    framework fetched from this checkout's `HEAD` by local git URL. CI therefore tests exactly the
    commit, with no network.
  - **README** rewritten: install, starting an app, commands, layout.
- 2026-11-26, **W3 progress.**
  - **W3.1, done:** PLAN.md's decision table records what was not built and why.
  - **W3.2, partly done.** The Stage 6 "leaves opaque" item turned out to be a real gap, now closed.
    - `#audit_verified` checked only declarations *inside* the verified modules. A verified function
      calling an outside helper with `@[implemented_by]`, or `@[extern]` with a body, passed: the
      kernel checks the body, the binary runs other code.
    - The audit now walks every verified declaration's dependencies outside the verified modules
      and the core library. An `@[extern] opaque` leaf (LeanKV's C leaf) stays allowed.
      Compiler-generated `ctorIdx` is skipped: a first version flagged it in Ledger.
    - Also new: an audit whose prefix matches nothing now fails. It used to report "OK (0 theorems)";
      found when my own new test forgot an import.
    - Both are frozen negative tests in `lean/MakeItLeanTest/Gates.lean`, and Ledger, Counter and
      LeanKV still pass.
    - **Not done:** `mil selftest` (a mutation list as a gate) and the TypeScript shell template.
      Both are larger, and not needed before W4.
  - **W3.4, done:** `knowledge/LEAN_IDIOMS.md` gained eight items (Lake, runtime, dot notation and
    the two-workspace trap). The new `knowledge/DESIGN_LESSONS.md` distils the design lessons from
    the friction logs. AGENTS.md links it, and asks roles to mark friction rows `idiom:`, `lemma:` or
    `lesson:` for the orchestrator to move into `knowledge/`.
  - **W3.5, done.**
    - **Lock coverage:** `mil check-lock` also requires that `spec.lock` lists exactly
      `mil.json`'s lock set. Ledger's lock and the 8 bench locks already do. Negative test in
      `all.sh` 8c: drop a line, edit the file, expect a MISMATCH.
    - **`fillSorry`, analysed:** every failure mode fails closed (`mil` stops, or the comparator
      rejects), so no more tests.
  - **Guard friction from the W1 spike, fixed:** inline-interpreter code now counts only the paths
    in its own segment (arguments, `-c`/`-e` code, heredoc bodies), not the whole command. Five new
    cases: the exact false positive, plus true writes by `-c`, by heredoc with an argument, and
    after a read; test_guards 134/134. A conservative block remains by design: inline Python that
    names a frozen file, even to read it.
- **2026-11-25 · W4 (Experiment B), set up.** The user approved the Stockroom brief and protocol
  above.
  - **CI fix (6aeca02):** CI now checks out the full history. Lake's git fetch (`--filter=tree:0`)
    hangs against a shallow repository, which made `all.sh` step 9 fail in CI.
  - **Setup:** `~/stockroom-exp/` (its own git repository, outside the checkout).
    `mil init --agent codex Stockroom stockroom` pins the framework to `6aeca02` on GitHub.
  - **Install path checked before the run:**
    - the dependencies were fetched from GitHub and built (spec 35 s, impl 25 s, one shared clone);
    - the untouched template was judged ACCEPTED.
  - **Codex** CLI 0.172 (Linux build). The user runs it interactively and answers the gates alone.
  - **Run notes.**
    - Stage 0: Codex stopped with a draft `REQUIREMENTS.md` and `[DECIDE]` items; the user answered alone.
    - Stage 2: Codex stopped before freezing (no `spec.lock`), but did not run `mil review` or show
      `SPEC_REVIEW.md` as AGENTS.md says; the user generated it.
    - **Framework bug found:** `mil review` failed on an external app (the git copy of
      `MakeItLean.Review` was never built). Fixed mid-run, since `mil` is not part of the app's pin:
      it now runs `lake build <spec> MakeItLean.Review` first; `all.sh` step 9 now runs `mil review`.
- Friction: the lock guard blocks a *read-only* command that names a frozen file when the same
  command has an inline `python3 -c` (the inline-interpreter rule counts every named file as
  written). Seen with `grep … examples/kvstore/lakefile.lean; python3 -c …`. Workaround: split
  the command. To fix in W3: count a file only if the inline code names it.
