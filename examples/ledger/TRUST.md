# Ledger — Trust report (Stage 6)

Spec frozen as **ledger-v1** (`spec.lock`, 7 files). `mil judge`: **ACCEPTED** (the comparator checks
`impl_pick_ok` against the frozen spec). `mil audit`: **AUDIT PASSED**. The audit runs the lock
check, the spec gates, the comparator in paranoid mode, and the verified-code audit of
`LedgerImpl.Core`, `LedgerImpl.Proofs` and `LedgerSol`. That last check confirms they use only the
standard axioms, have no `sorry`, `partial`, `unsafe`, `opaque`, `implemented_by` or `extern`,
and do not import the shell.

**Proven** means a Lean theorem, checked by the comparator or compiled in the frozen spec, using
only `propext`, `Quot.sound` and `Classical.choice`. **Tested** means exercised on real files by
`impl/test.sh` (`tests/cli_test.sh`: 74 checks; `tests/kill_test.py`: 2 × 300 commands, about
half of them SIGKILLed). **Trusted** means neither.

## Requirement by requirement

| Req | What | Status | Evidence |
|---|---|---|---|
| R1 | Accounts, at most one per name, empty at start | Proven | `LState.Good` (names strictly ascending), `reachable_good`; empty ledger = `[]`, `good_empty` |
| R2 | Names: 1–64 bytes of `[A-Za-z0-9._-]`, case-sensitive | Proven (model), tested (CLI) | `validName`, `nameByte`; `#guard`s for 64/65 bytes and bytewise order; cli_test: "", 1, 64, 65 bytes, space, `é`, `/` |
| R3 | 0 ≤ balance ≤ MAX = 2⁶³−1 | Proven | `maxBalance`; balances are `Nat`; `reachable_bal_le` |
| R4 | Amount 1…MAX, else `BAD_AMOUNT`; digits only on the CLI | Proven (rule), tested (parsing) | `validAmount`, `plan`; cli_test: 0, 1, MAX, MAX+1, 26 digits, `-5`, `+5`, `12.50`, `""`, `"1 2"` |
| R5 | Total = sum of balances, unbounded | Proven (definition) | `LState.total`; cli_test: a total of 2·MAX |
| R6 | `open` | Proven | `open_ok`, `plan_write_cases`, examples 1–3, 15 |
| R7 | `deposit` | Proven | `deposit_ok`, `plan_write_cases`, examples 4, 14, 16 |
| R8 | `withdraw`, never below 0 | Proven | `withdraw_ok`, `withdraw_too_much`, examples 12–13 |
| R9 | `transfer`: one step, both sides, or nothing | Proven | `transfer_ok`, `transfer_too_much`, `transfer_conserves`, `refused_unchanged`; on disk it is one atomic LeanKV `batch` (`writeCmd`, `step_writeCmd`) |
| R10, R10a, R10b | `balance`, `accounts`, `total` change nothing | Proven | `reads_unchanged`, examples 6–7, 17–18 |
| §3 error order | First applicable error is reported | Proven (definition), checked | `plan` checks in the table's order; `#guard`s in `Properties.lean`; cli_test |
| R11 | All-or-nothing; only named accounts change | Proven | `refused_unchanged`, `only_named_change` |
| R12 | Bounds on every reachable ledger | Proven | `cstep_good`, `lrun_good`, `reachable_good`, `reachable_bal_le` |
| R13 | Conservation; total = deposits − withdrawals | Proven | `cstep_total`, `transfer_conserves`, `lrun_total`, `reachable_total`; also checked in `kill_test.py` |
| Layout (§6) | The store stands for the model ledger | Proven | `decodeBal_u64le`, `dec_insert`, `bal_dec`, `pickRef_refines` (every store), `kvRun_refines` |
| Implementation | Fast `pick` = reference `pickRef` | Proven, comparator ACCEPTED | `LedgerImpl.pick_ok` (fills `impl_pick_ok`), `look_eq` (balanced-tree lookup = reference lookup) |
| R15 | Acknowledged commands persist | Proven (via LeanKV), tested | `LedgerImpl.pickOk` makes LeanKV's `substrate_crash_consistent` / `substrate_no_faults` apply to Ledger; `runPick_refines` maps the stored state to `lrun`. kill_test: every acknowledged command is visible afterwards |
| R16 | After a crash: acknowledged prefix, plus maybe the in-flight command, never half a transfer | Proven (via LeanKV), tested | Same chain: `substrate_crash_consistent pickOk` says the log stands for `runPick ledgerPick s0 (cs.take j)` or `(cs.take (j+1))`; `runPick_refines` says that store decodes to the model ledger after those commands. kill_test: 280 kills, 17 applied before the kill, none half-applied |
| R17 | Torn tail cut silently; corruption refuses (exit 3) without changing the file | Proven in LeanKV (recovery); tested here | LeanKV's recovery theorems (`examples/kvstore/TRUST.md`); cli_test: a damaged first record gives `ERR CORRUPT`, exit 3, file unchanged; a torn last record is dropped |
| R14 | CLI grammar, answer lines, exit codes 0–4 | Tested | cli_test (all commands, all error codes, exit codes 0/1/2/3/4) |

## Trusted, not verified (the boundary)

1. **The CLI shell, `impl/LedgerImpl/Shell.lean`.** It covers argument parsing (`parseCmd`,
   `parseAmount`), answer formatting (`render`, `errText`, `nameText`) and exit codes. It also
   covers **how answers are printed**: the shell prints `cstep (dec index) c` on the ledger as it
   stood before the command, where `index` is LeanKV's index after recovery. The function is the
   spec's own `cstep`, and the index is proven to equal the reference store. But the wiring is
   unproven: the shell calls `cstep` on the right pre-state, prints the answer only after the write
   succeeded, and maps an I/O reply to `ERR IO`. There is no end-to-end proof of the shell. It is
   covered by tests only.
2. **The composition of the link theorems.** Each link is proven: `pickOk` gives
   `substrate_crash_consistent` for Ledger, `runPick_refines` and `kvRun_refines` move from the
   store to the model, and `reachable_*` give R12 and R13 on that model. No single Lean theorem
   states "the real ledger directory after a crash equals `lrun` of the acknowledged commands".
   That last step of composition is checked by hand, not by Lean.
3. **LeanKV's own trust base** (`examples/kvstore/TRUST.md`). This is the model file system and
   crash model, the C file layer (`lkv_io.c`), and `fsync` and the operating system.
4. **The Lean compiler and runtime.** This includes `Nat` arithmetic on large numbers and the
   compiled code of `cstep` and `pick`.
5. **Exclusive access.** Only Ledger writes `<dir>/leankv.log`, and only one Ledger process uses
   `<dir>` at a time (§6, §8). Stores that Ledger never wrote are outside the R12/R13 scope (§4).
   `pickRef_refines` still holds for them, because `decodeBal` reads at most 8 bytes.

## Not covered by any proof
- Speed and memory. The rule logic uses `LeanKV.Core.lookup` on the balanced index: O(log n) per
  lookup. Printing an answer evaluates `cstep` on the decoded ledger, which is O(n) per command, on
  top of LeanKV's replay of the whole log at open. Nothing is benchmarked; Ledger has no performance
  requirement.
