# Building a program with MakeItLean: a guide for developers

MakeItLean lets an AI coding agent build a program **spec-first in Lean 4**. You say what the program
must do; the agent writes a precise spec; you approve it; then the agent writes the code and proves
it meets that spec, and `mil` checks the proofs independently. You do two things nobody else can:
approve the requirements, and sign off the spec. This guide is about doing both well.

- What an audit guarantees and what it does not: [GUARANTEES.md](GUARANTEES.md).
- The agent's own instructions: [agents/AGENTS.md](../agents/AGENTS.md) (you do not need to read them).

## 1. Install
**Linux or WSL (native):**
```bash
curl -sSfL https://raw.githubusercontent.com/leanprover/elan/master/elan-init.sh | sh -s -- -y --default-toolchain none
sudo apt-get install -y bubblewrap python3 git
git clone https://github.com/iliketocode2/MakeItLean.git ~/MakeItLean
cd ~/MakeItLean/cli && lake build
export PATH="$HOME/MakeItLean/cli/.lake/build/bin:$PATH"
mil doctor
```
On Ubuntu 24.04, `mil doctor` may report that bubblewrap cannot create a sandbox. The fix it prints
(`sudo sysctl -w kernel.apparmor_restrict_unprivileged_userns=0`) changes a system-wide security
setting; if you would rather not, use the container.

**macOS, Windows, or Linux without changing the host: the container.**
```bash
git clone https://github.com/iliketocode2/MakeItLean.git && cd MakeItLean
docker build -t makeitlean .
cd /path/to/your/project
/path/to/MakeItLean/tools/mil-docker mil doctor     # any command; no arguments: a shell
```
Inside the container, `mil`, `lake` and everything the checks need are installed, and your current
directory is at `/work`. Run your agent's commands there too (for example, start the agent inside the
container's shell). The container is tested on Linux with Docker; Docker Desktop on macOS runs the
same Linux image, but has not been tested by us yet.

`mil doctor` checks every requirement and prints the fix for anything missing. Run it first whenever
something behaves oddly.

## 2. Start a program
Pick the template closest to your program:

| Your program | Command | What the spec looks like |
|---|---|---|
| A library of related functions | `mil init --lib MyLib mylib` | a simple reference implementation of each function; the code may be faster, but must be proven equal to it |
| One function | `mil init --pure MyFn myfn` | a precondition and a postcondition |
| A command-line program that keeps data on disk and survives crashes | `mil init MyApp myapp` | a model of the state, each command's effect, and how state is stored |

Add `--agent claude` (Claude Code, with hooks that stop agents editing frozen files) or `--agent codex`
(Codex, instructions only). Run `mil init` in your own repository, outside the MakeItLean checkout:
the app then pins the framework's exact commit, which must be pushed (`mil doctor` tells you).

Then start your agent in the new directory and describe what you want, in a paragraph. Other
kinds of program (in-memory services, file-processing tools, servers with several writes per
request) do not have templates yet.

## 3. Your first gate: the requirements (Stage 0)
The agent writes `REQUIREMENTS.md` and stops. It writes no Lean before you approve. Check:
- **Every behaviour you care about has an ID** (R1, R2…) and at least one worked example with exact
  inputs and outputs.
- **Every `[DECIDE]` item is answered.** These are the questions the agent could not settle from your
  description: answer each one explicitly.
- **Limits are stated:** sizes, maximum values, what happens at the limit (refused? capped?).
- **Errors are stated:** which errors exist, their exact text, and which one wins when several apply.
- **Non-goals are listed.** Anything not required is not proven.

Approve only when you would be happy if the program did exactly this and nothing more.

## 4. Your second gate: the spec (Stage 2)
The agent writes the Lean spec, proves its properties, tries to break it (the critic), runs
`mil review`, and shows you `SPEC_REVIEW.md`. You do not need to read Lean fluently: every definition
and theorem carries an English sentence next to it. Check:
- **Coverage:** each requirement in `REQUIREMENTS.md` has a definition, a theorem or a `#guard` example
  that states it. A requirement with nothing in the spec is not guaranteed.
- **The English matches the Lean** for the definitions that matter most (the commands, the errors,
  the limits). Ask the agent to explain any line you are unsure of.
- **The worked examples** appear as `#guard` lines with your exact numbers.
- **The critic's planted bugs** (at the end of the review): each is a plausible mistake the spec
  rejects. If a mistake you can imagine is missing, ask for it to be added.
- **Holes and obligations** (the `Contract` section): what the implementation must provide and the
  theorem it must prove. A weak obligation is the most expensive mistake to miss.

When you are satisfied, sign off. The agent (or you) runs `mil freeze mil.json <your name>`: the spec is
now locked, and any change to it needs your sign-off again.

## 5. While the agent works
- `mil check mil.json` (about a minute): everything the audit checks except the lock, the paranoid
  checker and the shell self-test. The agent's development loop.
- `mil audit mil.json` (a few minutes): the release check. It needs the frozen spec.
- When it prints **AUDIT PASSED**, read `TRUST.md`: each requirement with its status (Proven, Tested
  against the model, Tested, Trusted) and the evidence. See [GUARANTEES.md](GUARANTEES.md).

## 6. Changing your mind, and upgrading
- **A new feature** starts at Stage 0 again: a new version of the requirements, your approval, and if
  the spec changes, a new spec sign-off (the old lock is kept).
- **A new framework version:** `mil upgrade mil.json` shows what would change; `--apply` does it.
  Locked files change, so the spec needs a new sign-off. See [COMPATIBILITY.md](COMPATIBILITY.md).

## 7. When `mil` fails
| `mil` says | What it means | What to do |
|---|---|---|
| `spec.lock MISMATCH` | a frozen file changed after sign-off | restore it from git; a real change needs a new sign-off |
| `REJECTED: … sorryAx` / `statement do not match` | a proof is missing, or a theorem was changed | the agent finishes or fixes the proof; it must not change the frozen statement |
| `REJECTED (no error lines: check the environment …)` | the checker's sandbox could not start | `mil doctor`; inside another agent's sandbox, run `mil` outside it |
| `dependency check: …` | the implementation's build setup differs from the spec's | restore `impl/lakefile.lean` (it requires only the spec package) and run `lake update` in `impl/` |
| `Verified-code audit FAILED: implemented_by / extern / partial …` | verified code would run something other than what was proven | remove the construct from verified code |
| `Contract gate FAILED` | the spec's holes or obligations differ from `mil.json` | fix the spec before the freeze |
| `spec critic: … is missing` / `no #guard` | nobody tried to break the spec | the critic adds planted bugs in `<App>/SpecCritic/` |
| `Trust rules FAILED: row …` | `TRUST.md` claims more than its evidence | cite the theorem that proves it, or lower the status |
| `selftest: FAILED (the shell disagrees with the model)` | the shell's answer differs from the spec's, on the shrunk sequence shown | fix the shell (`Text.lean`, `Shell.lean`) |
| `selftest: FAILED (mutation score below the minimum …)` | the tests miss changes to the shell (listed as survivors) | strengthen the tests in `impl/tests/`; never weaken the generator |
| `Surviving mutants not explained in TRUST.md` | a change no test catches is not explained | add the survivor (`Shell.lean:21`) and the reason to `TRUST.md` |
| `selftest: an earlier run was interrupted` | a `.mil-orig` backup is left over | copy it back over the file it names, then rerun |
| `this app is for framework X, but this mil is Y` | your framework checkout is older than the app | update the checkout (`git pull`, rebuild `mil`) |
| `… audits apps for framework … or later. Run mil upgrade` | the app predates what this `mil` supports | `mil upgrade` (then a new sign-off) |
| `not a known legacy audit` | an app from before 0.6.0 | `mil upgrade` |
| `commit … is on no remote branch` | the app pins a framework commit nobody can fetch | push the framework checkout, or set `MIL_GIT_URL` |
