# MakeItLean

A framework that lets AI coding agents build applications **spec-first in Lean 4**.

- **Specs first.** A human approves plain-English requirements. An agent turns them into a Lean
  spec, and a second agent tries to break it with planted wrong implementations. The human signs
  off on a side-by-side review (English next to each Lean definition), and the spec is frozen by
  hash.
- **What runs is proven or tested.**
  - The implementation is proven against the frozen spec, judged by `lake comparator` (sandboxed,
    with independent kernels).
  - Code that is not proven, such as a TypeScript HTTP shell, is differentially tested against the
    Lean reference model.
  - `TRUST.md` says which is which.
- **Agents cannot cheat quietly.**
  - Each app's audit rejects `sorry`, custom axioms, `native_decide`, weakened statements and
    redefined spec definitions.
  - For Claude Code, hooks block edits to frozen files and keep each agent role to its own files.

Status: research prototype, version 0.6.0 ([versions and compatibility](docs/COMPATIBILITY.md)).

**New here? Read [docs/GUIDE.md](docs/GUIDE.md)**: installing, choosing a template, the two
approvals only you can give, and what to do when `mil` fails. What an audit does and does not
guarantee: [docs/GUARANTEES.md](docs/GUARANTEES.md). The design is in [docs/PLAN.md](docs/PLAN.md),
current work in [docs/PHASE6.md](docs/PHASE6.md).

## Install

Linux or WSL natively (native Windows Lean is blocked by Smart App Control), or anywhere with
Docker through the container: `docker build -t makeitlean .`, then `tools/mil-docker <command>` in
your project ([guide](docs/GUIDE.md#1-install)).

```bash
# Lean (elan); each project pins v4.36.0 in lean-toolchain
curl -sSfL https://raw.githubusercontent.com/leanprover/elan/master/elan-init.sh | sh -s -- -y --default-toolchain none
# the comparator's sandbox; on Ubuntu 24.04 unprivileged user namespaces may need enabling:
#   sudo sysctl -w kernel.apparmor_restrict_unprivileged_userns=0
sudo apt-get install -y bubblewrap python3

git clone https://github.com/iliketocode2/MakeItLean.git ~/MakeItLean
cd ~/MakeItLean/cli && lake build          # builds `mil`
export PATH="$HOME/MakeItLean/cli/.lake/build/bin:$PATH"
mil doctor                                 # checks everything above, prints the fix for what is missing
```

`mil` finds the framework from where it was built. Set `MIL_HOME` to use another checkout.

## Start an app

Anywhere outside the checkout (your own repository):

```bash
mil init --lib --agent claude MyLib mylib    # a library of related functions
mil init --pure --agent codex MyFn myfn     # one pure function
mil init --agent claude MyApp myapp         # a command-line app on the LeanKV durable store
```

- **The framework comes by git.** The app's lakefiles require the framework by git URL, pinned to
  the checkout's current commit, so builds are reproducible. Commit and push the framework first,
  or `lake update` cannot fetch that commit. `MIL_GIT_URL` and `MIL_GIT_REV` override the source.
- **`--agent claude`** writes:
  - `CLAUDE.md`;
  - the role agents (`.claude/agents/mil-*.md`);
  - `.claude/settings.json`, whose guard hooks enforce frozen files and role areas.

  Start Claude Code in the app directory.
- **`--agent codex`** writes `AGENTS.md`. Codex has no hooks, so the only enforcement is
  `mil check-lock` and `mil audit`.

Then follow the stages in [agents/AGENTS.md](agents/AGENTS.md):

| Stage | What happens | Command |
|---|---|---|
| 0 | Requirements (`REQUIREMENTS.md`) | the user approves them |
| 1–2 | The spec, critic, review and sign-off | `mil review`, then `mil freeze mil.json <who>` |
| 3–4 | Implementation and proofs | `mil check mil.json` (fast loop), `mil judge mil.json` |
| 5–6 | Shell, tests, self-test, audit and `TRUST.md` | `mil selftest mil.json`, then `mil audit mil.json` |

## Commands

```
mil init [--pure|--lib] [--agent claude|codex] <AppName> <dir>
mil check | review | contract | solution | judge [--paranoid] | check-lock | selftest | audit [--allow-unfrozen] <app>/mil.json
mil freeze <app>/mil.json <who>
mil upgrade [--apply] <app>/mil.json        move an app to this framework version
mil doctor | --version
mil comparator [--paranoid] <impl_dir> <config.json>
```

`mil judge` runs `lake comparator` in a **staged judge workspace**: a temporary copy of only the
app's packages, deleted afterwards (`MIL_KEEP_JUDGE=1` keeps it).

## Layout

| Path | What |
|---|---|
| `lean/` | gates (English docs, holes, spec axioms, contract, verified-code audit) and the review generator |
| `cli/` | `mil`, in plain Lean with no dependencies |
| `templates/` | app templates: `lib/` (library), `pure/` (one function), `app/` (LeanKV substrate) |
| `agents/AGENTS.md`, `.claude/` | agent workflow, roles, guard hooks (`tools/hooks/`) |
| `examples/` | LeanKV (the durable substrate), Counter, Ledger (with a TypeScript HTTP shell) |
| `knowledge/` | Lean 4.36 idioms and an index of reusable lemmas |
| `tests/all.sh` | every check (CI runs it); `tests/cheats/`: every known way to a false AUDIT PASSED, each rejected |
| `Dockerfile`, `tools/mil-docker` | the container |

## License

MIT, see [LICENSE](LICENSE).
