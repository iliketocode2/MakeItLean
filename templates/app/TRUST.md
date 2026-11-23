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
| R3 | Acknowledged increments persist; after a crash, the state is exactly the acknowledged commands plus possibly the one in flight | Proven on LeanKV's model file system, tested | `AppNameImpl.crash_consistent` (LeanKV's `app_crash_consistent` with `pickOk` and `refines`, pinned to the frozen spec in `impl/audit.lean`); `kill_test` |

## Trusted, not verified

1. **The CLI shell, `impl/AppNameImpl/Shell.lean`:** argument handling, printing and exit codes. It
   prints `cstep` on the decoded state before the command. That function is the spec's own, but
   the wiring is tested (`cli_test`), not proven.
2. **LeanKV's trust base** (`examples/kvstore/TRUST.md`): the model file system and crash model,
   the C file layer, `fsync` and the operating system.
3. **The Lean compiler and runtime.**
4. **Only AppName writes `<dir>/leankv.log`.**
