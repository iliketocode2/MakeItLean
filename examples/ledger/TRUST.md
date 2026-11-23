# Ledger — Trust report (Stage 6, v3)

Spec frozen as **ledger-v1** (`spec.lock`, 7 files), unchanged in v3. `mil judge`: **ACCEPTED**
(the comparator checks `impl_pick_ok` against the frozen spec). `mil audit`: **AUDIT PASSED**. The
audit runs the lock check, the spec gates, the comparator in paranoid mode, and the verified-code
audit of `LedgerImpl.Core`, `LedgerImpl.Proofs` and `LedgerSol`. That last check confirms they use
only the standard axioms, have no `sorry`, `partial`, `unsafe`, `opaque`, `implemented_by` or
`extern`, and do not import the shell.

v3 (REQUIREMENTS.md R18–R20, `http/REQUIREMENTS.md`) adds serve mode, the oracle and the HTTP
JSON API. **v3 adds nothing proven.** The proven rows below are the same as in v2. Serve mode and
the HTTP API are **tested against the model**, and the code they run outside the proven core is
**trusted**.

There are four statuses:
- **Proven** means a Lean theorem, checked by the comparator or compiled in the frozen spec, using
  only `propext`, `Quot.sound` and `Classical.choice`.
- **Tested against the model** means a differential test: random command sequences go to the real
  system and to `ledger-oracle` (the frozen spec's `cstep` from the empty ledger, as a process),
  and every answer must be equal. A planted-bug check shows the test can fail.
- **Tested** means checked on real files against expected answers written from the requirements.
- **Trusted** means neither proven nor tested in full. It is assumed, argued, or covered only in
  part by tests.

## Test runs behind this report (auditor's own runs, 2026-11-22)

| Suite | Command | Result |
|---|---|---|
| Build | `lake build ledgerCli ledgerOracle LedgerImpl` in `impl/` | build completed |
| CLI and kill tests (unchanged) | `impl/test.sh` | cli_test 74 passed, 0 failed; kill_test 2 × 300 commands, 131 and 142 kills (21 and 23 applied before the kill), all consistent |
| V1: serve against the model | `impl/tests/serve_test.sh` | gen_coverage: 30 × 200 reach all 29 required cases; difftest serve vs oracle 30 runs × 200 commands, seeds 1 and 2, agree on every answer; serve_test 12 passed, 0 failed |
| V8: no dependencies | `http/test.sh` | 34 imports, all `node:` or local; no package.json, no node_modules |
| V2: HTTP against the model | `http/test.sh` (difftest through `http/adapter.ts`) | 30 runs × 200 commands, seeds 1 and 2, agree on every answer |
| V3: planted bugs | `http/test.sh` (planted_bug) | 4 of 4 mutants caught (from/to swapped, INSUFFICIENT_FUNDS shown as BALANCE_LIMIT, UNKNOWN_ACCOUNT as 422, balances through a JavaScript number); 8 passed, 0 failed |
| V4: literal examples | `http/test.sh` (replay) | E1–E35 read from `http/REQUIREMENTS.md` and replayed byte for byte, with the protocol line each sends; 417 passed, 0 failed |
| V5: HTTP-only cases | `http/test.sh` (edge_test) | 91 passed, 0 failed |
| V6: HTTP kill test | `http/test.sh` (kill_test) | 2 runs, 600 requests, 51 SIGKILLs (49 with a request in flight, 25 of those applied); ledger always equal to the model; 602 passed, 0 failed |
| V7: audit | `mil audit examples/ledger/mil.json` | AUDIT PASSED under the unchanged ledger-v1 lock |

I also sent 18 probe requests of my own (lone surrogates, non-ASCII digits, `1_000`, `0007`,
U+2028 and U+00A0 in names, a duplicate key, a "\_\_proto\_\_" key, a 38-digit amount). Each answer
equalled the oracle's answer for the same line, or was the `400`/`422` that H7–H9 require.

## Requirement by requirement

### The Lean ledger (R1–R17, unchanged from v2)

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
| R15 | Acknowledged commands persist | Proven on LeanKV's model file system (one theorem), tested | `LedgerImpl.crash_consistent` (= LeanKV's `app_crash_consistent` with `pickOk` and `refines`; pinned to the frozen `dec`/`cstep`/`pickRef` in `impl/audit.lean`). Also `substrate_no_faults`, `runPick_refines`. kill_test: every acknowledged command is visible afterwards |
| R16 | After a crash: acknowledged prefix, plus maybe the in-flight command, never half a transfer | Proven on LeanKV's model file system (one theorem), tested | `LedgerImpl.crash_consistent`: after any faults and any crash, the recovered log decodes to the Ledger model after exactly the acknowledged commands, possibly plus the one in flight (`AppOutcome`). kill_test (this audit): 273 kills, 44 applied before the kill, none half-applied |
| R17 | Torn tail cut silently; corruption refuses (exit 3) without changing the file | Proven in LeanKV (recovery); tested here | LeanKV's recovery theorems (`examples/kvstore/TRUST.md`); cli_test: a damaged first record gives `ERR CORRUPT`, exit 3, file unchanged; a torn last record is dropped |
| R14 | CLI grammar, answer lines, exit codes 0–4 | Tested | cli_test (all commands, all error codes, exit codes 0/1/2/3/4). In v3 `impl/test.sh` and `impl/tests/cli_test.sh` are unchanged and still pass. The parsing and printing moved unchanged into `impl/LedgerImpl/Text.lean` (`parseCmd`, `parseAmount`, `render`, `errText`, `nameText`, `usageText`); the CLI prints through the same functions. The one CLI change is D7: `ledger <dir> serve` now starts serve mode instead of exit 2 (serve_test checks that `serve x` and `ledger serve` are still exit 2) |

### Serve mode, the oracle and the HTTP API (R18–R20, new in v3)

| Req | What | Status | Evidence |
|---|---|---|---|
| R18 | `ledger <dir> serve`: one answer line per input line, same answers as the CLI | **Tested against the model** (V1). Not proven | difftest serve vs oracle, 30 × 200 commands, seeds 1 and 2, all equal; gen_coverage: the sequences reach every command with each of its answers, all 8 error codes including `ERR USAGE`, amounts 0, 1, MAX, MAX+1, names of 1, 64, 65 bytes, a balance at MAX and a total above MAX (29 cases). Each command still runs through `LeanKV.Core.execPick` with the proven `LedgerImpl.pick`, and its answer is `cstep` on the decoded pre-state (`answer`, shared with the CLI). The loop itself (`serveLoop`, `serve`) is trusted |
| R18 stopping and errors | End of input exit 0; `ERR USAGE` continues; corrupt store `ERR CORRUPT offset p`, exit 3, no file changed; open failure one `ERR IO` line, exit 4; `ERR IO` mid-run then exit 4 | Tested (serve_test), trusted | serve_test: 12 checks (basics, persistence across runs, last line without newline, empty input, CLI after serve, `serve x`, corrupt store with file hash unchanged, open failure on `/proc`, oracle from empty). `ERR IO` *mid-run* from the real ledger was not produced (no way to fill the disk on demand). The code path in `serveLoop` (an I/O reply or an exception gives `ERR IO`, exit 4) is trusted. The HTTP side of it is tested with a stub ledger (V5) |
| R18 durability | A change is durable before its answer line | Proven for the write path, trusted for the loop, tested | The write goes through `execPick` with `pickOk`, as in the CLI, so `LedgerImpl.crash_consistent` covers the sequence of commands in one session. That the loop prints only after `execPick` returns, threads the new handle into the next command, and stops after an I/O error is trusted wiring. Tested by V6 (SIGKILL of the server and its serve process, 51 kills) |
| R19 | `ledger-oracle`: the frozen model as a process | Trusted (by construction), tested | `impl/LedgerImpl/Oracle.lean` imports only `LedgerImpl.Text`, which imports only the frozen `Ledger.Spec.Model`: no store, no files, no implementation code. It folds the spec's `cstep` from `[]`. serve_test checks it from the empty ledger. V4 checks that the oracle gives the documented answer for every protocol line of E1–E35. Its loop (a `partial def`, allowed outside verified code), the shared parser/printer and the compiler are trusted |
| R20 / H5–H11 | Every route, request-to-line mapping and answer-to-response mapping | **Tested against the model** (V2, V3, V4). Not proven | V2: difftest of the HTTP API (through `http/adapter.ts`) vs oracle, 30 × 200 commands, seeds 1 and 2, the same sequences and coverage as V1, all equal. V3: 4 planted mapping bugs, each caught. V4: E1–E35 byte for byte (status line, `Content-Type`, `Content-Length`, `Allow`, body, and the exact protocol line sent, or none). V4 catches a bug mirrored in both the server and the adapter, which V2 alone would miss |
| H7, H8 (`?` stand-in) | A name or amount string that cannot be one word is sent as `?`, and the answer is still the model's | Trusted (argued), tested | Not visible to the difftest: the adapter never produces such strings. The argument is in `http/REQUIREMENTS.md` H7/H8: every such name is invalid under R2, so is `?`, and `BAD_NAME` is checked first; every such amount is not plain digits, so is `?`, and parsing comes before every rule. Tested by E24, E25, E28 and edge_test (empty, space, tab, newline, NUL, DEL names; such amounts; bad name with bad amount gives `USAGE`; no protocol injection) |
| H1–H4, H6, H9 (server alone) | Arguments, startup, shutdown, fail-stop, body limit, malformed bodies, unknown paths and methods | Tested, trusted | The model never sees these. E27, E29–E34 and edge_test: 404 for `/open/`, `/open?x=1`, `/Open`, `/`, `//open`; 405 with `Allow: POST`; 65,536 bytes accepted, 65,537 refused 413 (also chunked), 413 before 400; malformed JSON, arrays, wrong types, missing and extra fields; empty body = `{}`; duplicate keys; bad arguments exit 2; corrupt directory exit 3 with no file changed; I/O error at startup and missing ledger binary exit 4; busy port exit 4; SIGINT/SIGTERM exit 0 and data survives restart; `ERR IO` (500, others 503, exit 4), an unmappable answer and a dying ledger (500 INTERNAL, others 503, exit 5) with stub ledgers |
| H13 | One command at a time, in arrival order | Tested, trusted | edge_test: 40 concurrent requests on separate connections are serialised; V6 and V2 run sequences one request at a time |
| H14 | A `2xx` answer from the ledger is durable | Tested, trusted | Rests on R18 durability above: the server responds only after the ledger's answer line. V6: after each SIGKILL of server and ledger, the restarted ledger equals the model after the answered commands, possibly plus the one in flight (25 of 49 in-flight commands were applied, none half-applied) |
| H15 | Exclusive use of `<dir>` | Trusted | Not enforced (R18, §6, §8) |
| R20 transport only | No ledger rule in TypeScript | Trusted (code review), tested | `http/server.ts` decides only path, method, body size and JSON shape (H9). Names and amounts are copied as text (only the `?` stand-in), numbers in answers are copied as digit strings and never converted (V3 mutant 4 shows a conversion would be caught). Reviewed by the auditor; not mechanically enforced |
| R20 standard library only | No npm packages | Tested (V8) | Every import is `node:` or local; no package.json, no node_modules |

## Trusted, not verified (the boundary)

1. **The CLI shell and serve loop, `impl/LedgerImpl/Shell.lean`.** It covers argument handling,
   exit codes, the serve loop (`serveLoop`, `serve`) and the wiring of answers: each command's
   answer is `cstep (dec index) c` on the ledger as it stood before the command (`answer`), where
   `index` is LeanKV's index. The function is the spec's own `cstep`, and the index is proven to
   equal the reference store. But the wiring is unproven: the shell calls `cstep` on the right
   pre-state, prints the answer only after the write succeeded, threads the new handle from one
   line to the next, and maps an I/O reply or exception to `ERR IO`. There is no end-to-end proof
   of the shell. It is covered by tests only (cli_test, serve_test, V1, V6).
2. **The shared line parser and printer, `impl/LedgerImpl/Text.lean`** (`parseCmd`,
   `parseAmount`, `words`, `render`, `errText`, `nameText`). The CLI, serve mode and the oracle all
   use it. **This is a blind spot of every differential test (V1, V2):** a bug here, for example
   reading an amount wrongly, would be the same in the system and in the oracle. What covers it is
   cli_test and the literal examples (V4), whose expected answers were written from the
   requirements, not from this code.
3. **The oracle's loop, `impl/LedgerImpl/Oracle.lean`.** The model it runs is the frozen `cstep`;
   the loop that reads lines and threads the state is trusted.
4. **The TypeScript HTTP server, `http/server.ts`.** Routing, body limits, JSON validation, the
   `?` stand-in, the answer-to-response table (H10), queueing (H13), startup probe, shutdown and
   fail-stop. Tested against the model (V2–V4) and by V5/V6, never proven. Its choices where the
   requirements left room (all consistent with the approved text): the startup probe is one empty
   line, which serve answers `ERR USAGE` without touching the store; a ledger that cannot start or
   exits during startup is exit 4, an unexpected probe answer exit 5; invalid UTF-8 or a BOM in a
   body is `400 USAGE`; after a 413 up to 1 MiB more is read and discarded, then the connection is
   dropped; an IPv6 host is bracketed in the listening line.
5. **The test adapter and helpers, `http/adapter.ts` and `http/tests/lib.ts`.** V2 depends on the
   adapter's inverse mapping. A wrong line-to-request mapping could hide a server bug; V4 (which
   does not use the adapter) and V3 limit that risk. An unknown command word in a line becomes a
   request to that path, and the server's `404 NOT_FOUND` is read back as `ERR USAGE`; so for those
   lines V2 checks only that the server refuses the path, not anything about the ledger.
6. **Node.js** (24, type stripping), its HTTP parser, and the operating system's sockets and pipes.
7. **The composition of the link theorems: closed** (as in v2). `LedgerImpl.crash_consistent` is
   one kernel-checked theorem: LeanKV's `app_crash_consistent` applied to `pickOk` and `refines`.
   `impl/audit.lean` pins both facts to the frozen spec's `dec`, `cstep` and `pickRef`. Remaining
   limits: it is checked by `mil audit` (kernel, standard axioms), not by the comparator, because a
   spec package cannot import the substrate; and it holds on LeanKV's model file system, so real
   files rest on item 8.
8. **LeanKV's own trust base** (`examples/kvstore/TRUST.md`): the model file system and crash
   model, the C file layer (`lkv_io.c`), and `fsync` and the operating system.
9. **The Lean compiler and runtime.** This includes `Nat` arithmetic on large numbers and the
   compiled code of `cstep` and `pick`, in the ledger and in the oracle alike.
10. **Exclusive access.** Only Ledger writes `<dir>/leankv.log`, and only one Ledger process (one
    CLI command, or one serve process under one HTTP server) uses `<dir>` at a time (§6, §8, H15).
    Stores that Ledger never wrote are outside the R12/R13 scope (§4). `pickRef_refines` still
    holds for them, because `decodeBal` reads at most 8 bytes.

## What the tests do not show

- **The model never sees the HTTP-only cases**: routes, methods, body size, malformed JSON, wrong
  JSON types (an amount sent as a number), and the `?` stand-in. Those are covered by the literal
  examples (V4) and edge_test (V5) only, against expected answers written from the requirements.
- **The shared parser/printer is on both sides** of V1 and V2 (boundary item 2).
- **Not produced with the real ledger:** an `ERR IO` in the middle of a serve session (a real
  disk-full or write failure). serve's handling of it is trusted code; the HTTP server's handling
  (500, then 503s, exit 4) is tested only against a stub ledger. A real I/O error at startup is
  tested.
- **Differential tests start from an empty directory.** Serve on an existing ledger is covered by
  serve_test (persistence across runs) and V6 (restarts after SIGKILL), not by V1/V2.
- **Retries.** A request whose connection drops may or may not have been applied, and retrying it
  can apply it twice (H14, a non-goal).
- **No authentication** (non-goal). The default address is `127.0.0.1`.

## Not covered by any proof

- Speed and memory. The rule logic uses `LeanKV.Core.lookup` on the balanced index: O(log n) per
  lookup. Printing an answer evaluates `cstep` on the decoded ledger, which is O(n) per command, on
  top of LeanKV's replay of the whole log at open. The HTTP server handles one command at a time
  (H13). Nothing is benchmarked; Ledger has no performance requirement.
