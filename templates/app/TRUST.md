# AppName — Trust manifest (Stage 6)

What each requirement rests on: **proven** (a Lean theorem, kernel-checked), **tested** (a named
test), or **trusted** (assumed, with the reason). `mil audit examples/appname/mil.json` re-checks
every claim, including that every theorem named here exists.

> TEMPLATE: this is the worked example's manifest with its names replaced. Rewrite every row for
> your app's requirements; `mil audit` checks that every theorem name cited here exists.

| Req | Requirement | Status | Evidence |
|---|---|---|---|
| R1 | `incr n` adds one and answers the new value; `get n` answers the value (0 if never incremented) | Proven, tested | `incr_answers`, `get_unchanged_model`; worked examples as `#guard` in `AppName/Spec/Properties.lean`; `cli_test` |
| R2 | Names are 1–64 bytes; appnames stop at 2⁶⁴ − 1 (a further increment is refused) | Proven, tested | `validName`, `maxCount`, `reachable_bounded`; `cli_test` (64 and 65 bytes) |
| Layout | The LeanKV store stands for the model's appnames | Proven | `decodeU64_u64le`, `pickRef_refines` |
| Implementation | Fast `pick` = reference `pickRef` | Proven, comparator ACCEPTED | `AppNameImpl.pick_ok` (fills `impl_pick_ok`), `countOf_eq` |
| Shell | `serve` and the CLI answer exactly as the model: parsing, the answer chosen, printing, state carried across commands | **Tested against the model** | `selftest` (`mil selftest`, run by `mil audit`): `appname <dir> serve` on real files vs `appname-oracle` (the spec's `cstep` from the empty state, `AppNameImpl/Oracle.lean`), 20 runs × 200 random commands from `gen_commands.py` (every command, the usage error, the name limits); then mutants that `mil` chose in `Text.lean` and `Shell.lean`, each run through that test and `cli_test`: score 20 of 24 (minimum 0.7); the 4 survivors are below |
| R3 | Acknowledged increments persist; after a crash, the state is exactly the acknowledged commands plus possibly the one in flight | Proven on LeanKV's model file system, tested | `AppNameImpl.crash_consistent` (LeanKV's `app_crash_consistent` with `pickOk` and `refines`, pinned to the frozen spec by `mil audit` from `mil.json`'s `audit` section); `kill_test` |

## Surviving mutants (selftest)

Mutants of the shell that no test catches, each explained. `mil audit` requires every survivor to
be named here.

- `Shell.lean:21`, `"ERR IO"` in `answer`: the line printed when a command's write fails. No test
  makes a write fail mid-run (it needs a full disk or fault injection); trusted.
- `Shell.lean:38`, exit code 4 after an I/O error in `serve`: same reason; trusted.
- `Shell.lean:55`, `return 2` in `let some c := c? | return 2`: unreachable (`c?` was checked
  just above); an equivalent mutant.
- `Shell.lean:58`, exit code 4 when a one-shot command's write fails: same as line 21; trusted.

## Trusted, not verified

1. **The shell, `impl/AppNameImpl/Shell.lean` and `impl/AppNameImpl/Text.lean`:** argument and
   line parsing, printing, exit codes and the `serve` loop. It prints `cstep` on the decoded state
   before the command. That function is the spec's own, but the wiring is **tested against the
   model** (`selftest`) and by `cli_test`, not proven. The oracle shares `Text.lean` with the shell.
   A bug written into `Text.lean` from the start would affect both equally and pass the
   differential test; `cli_test` checks the literal answer lines. (The self-test's mutants do not
   have this blind spot: the oracle is built before any mutation.)
2. **LeanKV's trust base** (`examples/kvstore/TRUST.md`): the model file system and crash model,
   the C file layer, `fsync` and the operating system.
3. **The Lean compiler and runtime.**
4. **Only AppName writes `<dir>/leankv.log`.**
