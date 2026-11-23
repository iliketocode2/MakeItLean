# Phase 3: hybrid and multi-agent (started 2026-11-22)

**Goal** (PLAN.md): an app with a non-Lean shell checked by differential tests against the Lean
model, built by separate agent roles whose write access is enforced.

## Decisions (user, 2026-11-22)
- **App:** an HTTP JSON API for Ledger, in **TypeScript**, **transport only** (Option A): every
  request becomes one command for the Lean ledger running as a long-lived `serve` process; the
  ledger rules stay in Lean. Node.js standard library only, no npm packages.
- **Roles:** fresh subagents per role (`mil-spec-author` → `mil-implementer` → `mil-auditor`), all
  working in one shared git worktree; write access enforced by `tools/hooks/guard_role.py` and
  `tools/hooks/guard_locked.py`. The orchestrator relays the user's answers verbatim and adds no help.

## Framework pieces built for it
- Line protocol (`Text.lean`), `serve` mode, model oracle (`<app>-oracle`), `tools/difftest.py`
  with shrinking, the "Tested against the model" status in `TRUST.md`; in the template and Counter.
- Enforced roles: `.claude/agents/mil-*.md`, `.claude/settings.json` hooks. Both guards find the
  repository from the target path, so they hold inside worktrees (40-case matrix: main and
  worktree, either working directory). Any `REQUIREMENTS*.md` of an app is spec-author area.
- `tests/all.sh` (every check) and `.github/workflows/check.yml` (CI).

## Exit-test brief (approved by the user, given verbatim to the spec author)
> Give **Ledger** (`examples/ledger/`, frozen spec `ledger-v1`) an HTTP JSON API written in TypeScript, in `examples/ledger/http/`. This reverses a v1 non-goal ("a server mode or network access"), so it starts with a change to the requirements for my approval. Every ledger operation must be reachable over HTTP with JSON request and response bodies: open, deposit, withdraw, transfer, balance, listing accounts and the total. Each kind of refusal should get a sensible HTTP status code. The TypeScript layer is transport only. All ledger rules stay in the existing Lean ledger, which the server keeps running as a long-lived process. The frozen spec is not touched, and the existing commands, answers and exit codes stay exactly as they are. Use the Node.js standard library only, with no npm packages. Show that the API answers exactly as Ledger's Lean reference model does, and state plainly in `TRUST.md` what is proven, what is tested and what is trusted. Include literal HTTP request/response examples in the API requirements. Work out the exact API with me before you write code.

## Run protocol
1. Live role-guard probe: a `mil-implementer` makes one allowed and one forbidden write.
2. **Stage 0** (`mil-spec-author`): the API requirements, for the user's approval.
3. **Build** (`mil-implementer`): Ledger's `serve` mode and oracle, the TypeScript server, the
   differential test through an adapter, and a replay test of the approved literal HTTP examples.
4. **Audit** (`mil-auditor`): `TRUST.md` and `mil audit`.
5. Orchestrator, after the test: wire the HTTP tests into `tests/all.sh` and CI (roles cannot edit
   framework files), and record friction.

## Pass criteria (fixed before the run)
1. HTTP differential test: the API, through its adapter, agrees with `ledger-oracle` over at least
   30 runs × 200 random commands reaching every operation and every refusal.
2. A planted-bug check: a deliberately wrong mapping makes the differential test fail.
3. **Literal replay:** every HTTP example in the approved API requirements is replayed verbatim
   (request in, exact status and body out) and passes. This closes the blind spot of a mapping bug
   mirrored in both the server and the adapter.
4. Ledger unchanged: Ledger's `mil audit` is AUDIT PASSED under the unchanged `ledger-v1` lock, and
   `impl/test.sh` (74 CLI checks, kill tests) passes.
5. `TRUST.md`: the HTTP layer and the adapter are "Tested against the model" or "Trusted", never
   "Proven"; the Lean core keeps its proven rows.
6. No dependencies outside the Node.js standard library.
7. No attempt to work around a blocked write (the friction log records every block).

## Known framework friction (orchestrator)
- The lock guard's Bash check blocks any command that both *mentions* a frozen path and contains a
  write operator, even when the write goes elsewhere (a heredoc that quotes the path into a doc).
  Workaround: write documents with the file tools. Possible fix: parse redirect targets instead.
