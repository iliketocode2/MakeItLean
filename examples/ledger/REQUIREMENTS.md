# Ledger — Requirements (Stage 0, v3: APPROVED 2026-11-22)

> Stage 0 of the MakeItLean workflow (`agents/AGENTS.md`). Plain English only. Every requirement
> has an ID (R1, R2, …) that the Lean spec will cite.
>
> **v2 was approved by the user on 2026-11-22.** D1–D6 were decided as recommended (recorded below
> as **Decided**). v2 added the `accounts` and `total` commands (R10a, R10b, D6) and stated the
> scope of the invariants (§4).
>
> **v3, approved by the user on 2026-11-22**, adds an HTTP JSON API. D7 was decided as
> recommended (a). The API's decisions are recorded in `http/REQUIREMENTS.md` §10: H-D2 went to
> (b), digit strings, and every other one went as recommended. Changes from here on need a new
> sign-off. It reverses the v1 non-goal
> "a server mode or network access" (§8). The changes are:
> - **R18** (new): a `serve` mode, `ledger <dir> serve`, that keeps the ledger open and answers one
>   command per input line.
> - **R19** (new): `ledger-oracle`, the frozen reference model as a process, used by the tests.
> - **R20** (new): the HTTP API itself, specified in full in
>   [`http/REQUIREMENTS.md`](http/REQUIREMENTS.md) (IDs H1–H16, literal examples E1–E35).
> - §7 and §8 are updated to match, and §9 records decision **D7**.
>
> **Unchanged in v3:** R1–R17, every command, answer, error code, check order and exit code of the
> one-shot CLI, the storage layout, and the frozen Lean spec `ledger-v1`. The reference model
> already decides every answer the API gives, so v3 needs no change to the spec and no new
> sign-off of it.

## 1. What it is
Ledger is a command-line bank ledger that keeps its state on disk. It holds named accounts, each
with a balance in whole cents. You can open an account, deposit into it, withdraw from it,
transfer between two accounts, and ask for a balance. Every command either succeeds completely or
changes nothing and says why. The state survives crashes: after a crash it shows exactly the
commands that were acknowledged, possibly plus the one in progress, and never half of a command.

"Double-entry" here means: a transfer is one entry that debits one account and credits another by
the same amount, so transfers never create or destroy money. Deposits and withdrawals are the only
way money enters or leaves the ledger (they are entries against "the outside world", which is not
an account in the ledger).

## 2. Data model
- **R1. Accounts.** The ledger holds a set of accounts. Each account has a **name** and a
  **balance**. At most one account has a given name. A new ledger has no accounts.
- **R2. Account names.** A name is 1 to 64 bytes, each an ASCII letter, digit, `-`, `_` or `.`.
  Names are case-sensitive (`Alice` and `alice` are different accounts). A command that uses an
  invalid name is refused with `BAD_NAME` and changes nothing.
  - **Decided D1:** this restricted character set (alternatives were any bytes, or any UTF-8 text).
- **R3. Balances.** A balance is a whole number of cents, never negative, and never more than
  **`MAX` = 9,223,372,036,854,775,807 cents (2⁶³ − 1, about 92 quadrillion dollars)**.
  - **Decided D2:** `MAX` = 2⁶³ − 1 (fits a signed 64-bit integer).
- **R4. Amounts.** An amount (for deposit, withdraw, transfer) is a whole number of cents from
  **1 to `MAX`**. Zero, or a number above `MAX`, is refused with `BAD_AMOUNT` and changes nothing.
  On the command line an amount is written as plain decimal digits (`1250` means $12.50). Signs,
  decimal points, spaces and other characters are a usage error (§5, R14).
  - **Decided D3:** whole cents only on the command line; no dollar amounts like `12.50`.
- **R5. Total money.** The *total* is the sum of all account balances. It is not stored and has no
  upper limit (only each single balance is bounded by `MAX`).

## 3. Operations
Each command answers either a success or exactly one error code. A refused command changes nothing.
When several errors apply, the **first** in the "checked in this order" column is reported.

| ID | Command | On success | Errors, checked in this order |
|---|---|---|---|
| R6 | `open NAME` | Creates account NAME with balance 0. Answers `OK`. | `BAD_NAME`; `ACCOUNT_EXISTS` (an account with that name already exists) |
| R7 | `deposit NAME AMOUNT` | Adds AMOUNT to NAME's balance. Answers `BALANCE b` with the new balance b. | `BAD_NAME`; `BAD_AMOUNT`; `UNKNOWN_ACCOUNT NAME`; `BALANCE_LIMIT` (new balance would exceed `MAX`) |
| R8 | `withdraw NAME AMOUNT` | Subtracts AMOUNT from NAME's balance. Answers `BALANCE b` with the new balance b. | `BAD_NAME`; `BAD_AMOUNT`; `UNKNOWN_ACCOUNT NAME`; `INSUFFICIENT_FUNDS` (balance < AMOUNT) |
| R9 | `transfer FROM TO AMOUNT` | In one step, subtracts AMOUNT from FROM and adds it to TO. Answers `OK`. | `BAD_NAME` (either name); `SAME_ACCOUNT` (FROM = TO); `BAD_AMOUNT`; `UNKNOWN_ACCOUNT FROM`; `UNKNOWN_ACCOUNT TO`; `INSUFFICIENT_FUNDS` (FROM's balance < AMOUNT); `BALANCE_LIMIT` (TO's new balance would exceed `MAX`) |
| R10 | `balance NAME` | Changes nothing. Answers `BALANCE b`. | `BAD_NAME`; `UNKNOWN_ACCOUNT NAME` |
| R10a | `accounts` | Changes nothing. Answers `ACCOUNTS n NAME1 B1 … NAMEn Bn`: the number of accounts, then every account and its balance, in ascending name order (bytewise, so `B` < `a`). | none |
| R10b | `total` | Changes nothing. Answers `TOTAL t`, the sum of all balances (R5). | none |

`UNKNOWN_ACCOUNT` names the account that does not exist, so a transfer says which side is missing.

- **Decided D4:** a transfer from an account to itself is refused with `SAME_ACCOUNT`.
- **Decided D5:** `deposit`/`withdraw` answer `BALANCE b` with the new balance; `open`/`transfer`
  answer `OK`.
- **Decided D6:** v1 also has `accounts` and `total` (R10a, R10b). Closing accounts is a
  non-goal (§8).

### Examples (these become executable checks in the spec)
Starting from an empty ledger, run in order:

| # | Command | Answer |
|---|---|---|
| 1 | `open alice` | `OK` |
| 2 | `open alice` | `ERR ACCOUNT_EXISTS` |
| 3 | `open bob` | `OK` |
| 4 | `deposit alice 1000` | `BALANCE 1000` |
| 5 | `transfer alice bob 300` | `OK` |
| 6 | `balance alice` | `BALANCE 700` |
| 7 | `balance bob` | `BALANCE 300` |
| 8 | `transfer bob alice 301` | `ERR INSUFFICIENT_FUNDS` (nothing changes) |
| 9 | `transfer alice carol 1` | `ERR UNKNOWN_ACCOUNT carol` (alice still 700) |
| 10 | `transfer alice bob 0` | `ERR BAD_AMOUNT` |
| 11 | `transfer alice alice 5` | `ERR SAME_ACCOUNT` |
| 12 | `withdraw bob 300` | `BALANCE 0` |
| 13 | `withdraw bob 1` | `ERR INSUFFICIENT_FUNDS` |
| 14 | `deposit carol 5` | `ERR UNKNOWN_ACCOUNT carol` |
| 15 | `open bad/name` | `ERR BAD_NAME` |
| 16 | `deposit alice 9223372036854775807` | `ERR BALANCE_LIMIT` (700 + MAX > MAX) |
| 17 | `accounts` | `ACCOUNTS 2 alice 700 bob 0` |
| 18 | `total` | `TOTAL 700` (= 1000 deposited − 300 withdrawn) |

## 4. Invariants (properties of the reference model, to be proven)
**Scope.** R12 and R13 are proven for every ledger *reachable from the empty ledger*: the empty
ledger, and anything obtained from it by running commands through the reference model. The
on-disk ledger is always such a state: a new `<dir>` starts from an empty log, every acknowledged
command moves the stored state exactly as the model does (§7, refinement), and recovery after a
crash yields the state after some prefix of the commands (R16). A LeanKV store holding arbitrary
bytes that Ledger never wrote is outside this scope (see the assumption in §6). R11 holds for
every ledger state.

- **R11. All-or-nothing.** A refused command leaves every account and balance exactly as it was.
  A successful command changes only the accounts it names: `open` creates one account, `deposit`/
  `withdraw` change one balance, `transfer` changes exactly two balances.
- **R12. Never negative, never over `MAX`.** After any sequence of commands, every balance is
  between 0 and `MAX`.
- **R13. Conservation.** A successful transfer leaves the total (R5) unchanged. A successful
  deposit of A raises the total by exactly A; a successful withdrawal of A lowers it by exactly A.
  `open` (balance 0), `balance` and every refused command leave the total unchanged.
  Consequence: after any sequence of commands, total = (sum of successful deposits) − (sum of
  successful withdrawals).

## 5. Durability and the command line
- **R14. Command line.** `ledger <dir> <command> <args…>`, where `<dir>` holds the ledger's files
  (created if missing). One command per run. The answer is printed as one line on stdout:
  `OK`, `BALANCE b`, `ACCOUNTS …`, `TOTAL t`, or `ERR <CODE> [detail]`.

  | Exit code | Meaning |
  |---|---|
  | 0 | Success (`OK`, `BALANCE`, `ACCOUNTS`, `TOTAL`) |
  | 1 | Refused by the rules in §3 (`ERR BAD_NAME`, `ERR BAD_AMOUNT`, …) |
  | 2 | Usage error: unknown command, wrong number of arguments, amount not plain digits (`ERR USAGE`) |
  | 3 | The data files are corrupt and the ledger refuses to open (`ERR CORRUPT`) |
  | 4 | I/O error, e.g. disk full (`ERR IO`); the command is not acknowledged |

  A success line is printed only after the change is durable on disk.
- **R15. Persistence.** Once a command has printed its success answer, its effect survives a crash
  or kill and is visible to every later command.
- **R16. Crash consistency.** After a crash at any moment, the ledger equals the result of running
  exactly the acknowledged commands, in order, plus possibly the one that was in progress, applied
  in full or not at all. A half-applied transfer (one side changed, the other not) is never visible.
  A command that failed with `ERR IO` is treated like the in-progress command.
- **R17. Corruption.** Ledger inherits LeanKV's recovery rules: a torn tail from a crash is cut off
  silently; corruption elsewhere makes the ledger refuse to open (exit 3) without changing any file.

### 5a. Serve mode, the oracle and the HTTP API (v3)
- **R18. Serve mode.** `ledger <dir> serve` opens the ledger once and then reads commands from
  standard input, one per line, and writes one answer line per command to standard output.
  - **Input lines** use the same words as the command line (R14): `open NAME`,
    `deposit NAME AMOUNT`, `withdraw NAME AMOUNT`, `transfer FROM TO AMOUNT`, `balance NAME`,
    `accounts`, `total`. Words are separated by one or more spaces. Amounts follow R4 (plain
    decimal digits).
  - **Answer lines** are exactly what the one-shot CLI prints for the same command on the same
    ledger: `OK`, `BALANCE b`, `ACCOUNTS …`, `TOTAL t`, `ERR <CODE> [detail]`. There are two
    differences. A line that is not a command (unknown word, wrong number of words, amount not
    plain digits) is answered with exactly `ERR USAGE`, with no usage text, and serve continues
    with the next line. An I/O error is answered with exactly `ERR IO`.
  - **Durability** is the same as for the CLI (R14–R16): a change is durable on disk before its
    answer line is written. Each answer line is flushed as soon as it is written.
  - **Stopping.** At the end of input, serve exits 0. After an I/O error it writes `ERR IO` and
    exits 4 without reading more lines. As in R16, the command that failed may or may not have
    been applied. If the data files are corrupt, serve prints `ERR CORRUPT offset p` and exits 3
    before reading any line, changing no file (R17). If the store cannot be opened, it prints a
    line starting with `ERR IO` and exits 4.
  - **The CLI is unchanged.** Every existing command, answer and exit code of R14 stays exactly
    as it is. The only new behaviour is that `ledger <dir> serve` starts serve mode. Before v3 it
    was a usage error (exit 2). `serve` was never a ledger operation (**Decided D7**).
  - One serve process uses `<dir>` at a time, and nothing else uses `<dir>` while it runs. This is
    the exclusivity assumption of §6 and §8. It is trusted, not enforced.
- **R19. The oracle.** `ledger-oracle` reads the same input lines and writes the same answer
  lines as serve mode. It answers every command with the frozen spec's reference model (`cstep`),
  starting from the empty ledger, and uses no files and no implementation code. Serve mode, the
  oracle and the one-shot CLI parse lines and print answers with one shared piece of code, so a
  comparison of serve (or the HTTP API) with the oracle compares like with like.
- **R20. HTTP JSON API.** A server written in TypeScript (`examples/ledger/http/`) gives HTTP
  access to every Ledger command, with JSON request and response bodies. It runs one
  `ledger <dir> serve` process for as long as it runs. The server is **transport only**: every
  ledger rule (names, amounts, balances, the check order of §3, durability) is decided by the Lean
  ledger, never by the TypeScript code. It uses the Node.js standard library only, with no npm
  packages. The exact API (routes, bodies, status codes, literal examples, startup, failures and
  verification) is [`http/REQUIREMENTS.md`](http/REQUIREMENTS.md). That document is part of these
  requirements.

## 6. Storage layout (how R14–R17 are achieved)
Ledger keeps its state in **LeanKV** (the substrate), in `<dir>/leankv.log`.
- One LeanKV key per account: **key = the account name** (1–64 bytes, a valid LeanKV key);
  **value = the balance as 8 bytes, least significant byte first**. An account exists exactly when
  its key is present.
- Each Ledger command becomes **exactly one** LeanKV command, chosen from the current contents:
  - `open` → `put NAME <0>`; `deposit`/`withdraw` → `put NAME <new balance>`;
  - `transfer` → one atomic `batch [put FROM <new>, put TO <new>]`;
  - `balance`, `accounts`, `total`, and every refused command → a read, which changes nothing
    (the answer is computed from the current contents).
- LeanKV's proven theorem `substrate_crash_consistent` then gives R15 and R16 for free, provided
  Ledger proves its translation is right (§7).
- **Assumption (trusted):** nothing but Ledger writes to `<dir>/leankv.log`.

## 7. What will be proven vs. tested vs. trusted
- **Proven** (Lean, checked by the comparator):
  - The reference model's behaviour R1–R13, including the examples of §3 (`#guard`), all-or-nothing
    (R11), the balance bounds (R12) and conservation (R13).
  - The balance codec round-trips for every balance 0…`MAX`.
  - **Refinement:** on every well-formed store, the LeanKV command chosen for a Ledger command
    changes the decoded ledger exactly as the reference model says.
  - **Implementation:** the fast translation (reading LeanKV's in-memory index) equals the
    reference translation. Together with LeanKV's `substrate_crash_consistent`: R15, R16, R17.
- **Tested:** the CLI on real files (every command and error of §3, the examples, exit codes,
  argument parsing, amounts at 0, 1, `MAX`, `MAX`+1, names of length 0, 1, 64, 65); kill-during-
  write tests on real files.
- **Trusted, not verified:** the CLI shell (argument parsing and printing), the operating system's
  file system and `fsync`, LeanKV's C file layer, the Lean compiler and runtime, and the assumption
  that only Ledger writes the store.
- **v3 additions** (detail in `http/REQUIREMENTS.md` §8):
  - Nothing new is *proven*. The proven rows above are unchanged, and the serve loop and the HTTP
    server are never described as proven.
  - **Tested against the model:** serve mode (R18) against `ledger-oracle` (R19), and the HTTP API
    (R20) against `ledger-oracle` through a line-protocol adapter. Both use differential tests on
    random command sequences. A planted-bug check shows the test can fail. Every literal HTTP
    example is replayed byte for byte.
  - **Trusted:** the serve loop and the shared line parser/printer, the TypeScript server and the
    test adapter, the Node.js runtime and its HTTP parser, the operating system's sockets, and
    exclusive use of `<dir>` by one serve process.

## 8. Non-goals (v1)
- Closing or renaming accounts; overdrafts or credit limits; interest and fees.
- Transaction history / a journal of past entries (only current balances are kept).
- Multiple currencies; fractions of a cent; negative amounts.
- Several processes using the same `<dir>` at the same time (one command at a time).
- Users, passwords, or permissions. This applies to the HTTP API as well: it has no
  authentication.
- ~~A server mode or network access.~~ **Reversed in v3:** serve mode (R18) and the HTTP API (R20)
  are now in scope. Their own non-goals are in `http/REQUIREMENTS.md` §9.

## 9. Decisions (2026-11-22)
D1–D6 approved as recommended. The double-entry framing (§1, R13), error codes and check order
(§3), exit codes (R14), storage layout (§6) and non-goals (§8) are confirmed as drafted. The
invariants' scope (§4) was clarified at the user's request.

### v3 decisions (user, 2026-11-22)
- **Decided D7:** serve mode is the subcommand `ledger <dir> serve` (option (a)), which is the
  framework's convention. `serve` was not an existing ledger operation, and every existing CLI
  command, answer and exit code stays unchanged. (Option (b) was a separate `ledger-serve`
  executable.)
- The HTTP API's decisions H-D1 to H-D10 are recorded in `http/REQUIREMENTS.md` §10. H-D2 went to
  (b): amounts, balances and totals are JSON strings of base-10 digits. Every other decision went
  as recommended.
- The `TRUST.md` boundary in §7 (and `http/REQUIREMENTS.md` §8) is approved as planned.
