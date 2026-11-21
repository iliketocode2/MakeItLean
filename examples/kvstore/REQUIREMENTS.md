# LeanKV — Requirements (Stage 0, v2: APPROVED 2026-11-21)

> Stage 0 of the MakeItLean workflow (see `docs/PLAN.md`). Everything here is plain English. Once you approve it, Stage 1 turns it into a Lean spec. Each requirement has an ID that the spec will cite.
>
> **v2 (2026-11-21):** The [DECIDE] items are resolved: R12 refuses unless the bad record is at the tail, R17 proves a height bound, and compaction and HTTP are parked (§8). Items marked **(proposed)** were added in v2 to close gaps found in review.
>
> **Approved by the user on 2026-11-21, including every (proposed) item.** Changes from here on need a new sign-off.

## 1. What it is
LeanKV is a single-process, persistent, ordered key-value store.
- It is used three ways: as a Lean library, through a command-line tool, and through a simple line-based server mode.
- The aims are to be simple enough to prove and fast enough to be worth benchmarking.
- v1 puts the core state machine, recovery and testability first, and keeps the proof surface small.

## 2. Data model
- **R1. Keys and values are byte strings.**
  - A key is 1–1024 bytes. A value is 0–1 MiB.
  - Anything outside these limits is rejected with a limit error, and nothing changes.
  - **(proposed)** The key limits apply to every operation that takes a key, including `get` and `delete`.
- **R2. Keys are ordered bytewise (lexicographically), as in LevelDB/RocksDB.**
  - `"a" < "ab" < "b"`.
  - The empty key is not allowed (see R1).
- **R3. The store holds at most one value per key.**

## 3. Operations
| ID | Operation | Meaning | Example |
|---|---|---|---|
| R4 | `get k` | Returns the value for `k`, or "not found". Never changes anything. | after `put a 1`: `get a` → `1`; `get b` → not found |
| R5 | `put k v` | Afterwards `get k` returns `v`. Every other key is unchanged. | `put a 1; put a 2; get a` → `2` |
| R6 | `delete k` | Afterwards `get k` is not found. Every other key is unchanged. Deleting a missing key is fine and does nothing. | `put a 1; delete a; get a` → not found |
| R7 | `scan lo hi limit` | Returns, in ascending key order, the pairs whose key is ≥ `lo` and < `hi`, at most `limit` of them. `hi` may be "unbounded". | keys a,b,c,d: `scan b d 10` → b,c; `scan a ∞ 2` → a,b |
| R8 | `batch [ops]` | A list of puts and deletes applied **atomically**: either all of them take effect, in order, or none do (for example, if any op violates R1). | `batch [put x 1, delete x, put y 2]` → x not found, y = 2 |

- **R7a (proposed). Scan edge cases.**
  - `lo` may be empty, which means "from the first key". Otherwise `lo` and a bounded `hi` follow the key length limit.
  - If `lo ≥ hi`, or `limit` is 0, the result is empty. That is a success, not an error.
  - `limit` is any non-negative integer.
- **R8a (proposed). Batch limits.**
  - A batch has at most 10,000 ops, and its keys and values total at most 64 MiB. The size is counted in raw key and value bytes, before any escaping or log framing.
  - The empty batch is allowed. It succeeds and changes nothing.
  - If any limit is violated, the whole batch is rejected and nothing changes.
- **R9. Determinism.** The answer to every operation depends only on the operations that came before it. "Real" behaviour is defined as: apply each operation in order to a simple sorted list of pairs.

## 4. Durability
- **R10. Persistence.** Once a write (`put`, `delete` or `batch`) reports success, its effect survives a process crash or kill and is visible after restart.
- **R11. Crash consistency.** After a crash at *any* moment, including halfway through writing a batch, the reopened store equals the result of some prefix of the successful writes, plus possibly the one in flight, applied in full or not at all. Partial batches are never visible.
  - **(proposed)** If a write fails with an I/O error (disk full, failed fsync), it is not acknowledged. It is then treated exactly like the in-flight write in a crash.
  - **(proposed)** After an I/O error, the open store refuses every further operation with `ERR IO` until it is reopened. A failed write may leave partial bytes in the log, and a later append would put good records after them, which R12 would then treat as corruption. Reopening runs recovery, which cuts those bytes off as a torn tail.
- **R12. Corruption detection: refuse unless it is a torn tail.** Recovery reads log records in order until the first record that fails to decode (bad header, bad length or bad checksum). Call that record's start offset `p`.
  - **Torn tail.** If no valid record can be decoded starting at *any* byte offset after `p`, the bytes from `p` on are a torn tail. The store opens with every record before `p`. Before it accepts new writes, it truncates the log at `p`, so new records never follow garbage.
  - **Corruption.** Otherwise there is a valid record after the bad one. The store refuses to open, changes nothing on disk, and reports the corruption with offset `p` (exit code 3).
  - **(proposed) Record format strength.** The chance that random bytes decode as a valid record must be at most 2⁻⁶⁰ per offset (for example, a magic number plus a 32-bit checksum, or a 64-bit checksum). This keeps false refusals negligible even across a 64 MiB torn batch.
  - **Accepted limitation.** Bit rot inside the *last* acknowledged record looks exactly like a torn write, so that record is dropped without an error. No log format can tell the two apart.
  - Checksum collisions are an accepted risk.

## 5. Interface
- **R20 (proposed). Library interface.** The same operations are available as a Lean library, so tests and tools can call them directly:
  - the pure **reference model**: a state plus a step function from (state, command) to (new state, response);
  - the **real store**: open a directory, run a command, close;
  - the pure **recovery function**: from log bytes to either "these records, with the tail ignored from offset p" or "corrupt at offset p". It is the same function the store uses on open, so it can be called on arbitrary bytes;
  - the **command parser and response printer** (R22);
  - **one function from response to exit code**, used by both the CLI and the server.
- **R14. CLI:** `leankv <dbdir> get|put|delete|scan|batch|check …`. The CLI prints the response line (R22) on stdout.
  - **Exit codes.** This table is the only definition. The CLI, `check` and `serve` all use it, through the single R20 function.

    | Code | Meaning | Response |
    |---|---|---|
    | 0 | Success, including an empty scan, deleting a missing key, and `check` finding at most a torn tail | `OK`, `VALUE`, `PAIRS`, `LOG` |
    | 1 | `get` found nothing | `NOTFOUND` |
    | 2 | Usage error (bad syntax) or limit error (R1, R8a) | `ERR USAGE`, `ERR LIMIT` |
    | 3 | Corruption: refusing to open (R12) | `ERR CORRUPT` |
    | 4 | I/O error **(proposed)** | `ERR IO` |
- **R21 (proposed). `check` command.** `leankv <dbdir> check` runs recovery read-only, never modifying the log. It reports one of:
  - the record count, the valid byte length, and the size of any ignored torn tail (exit 0);
  - the corruption offset (exit 3).
- **R15. Server mode:** `leankv <dbdir> serve` reads one command per line on stdin and writes one response per line on stdout. Benchmarks drive this mode.
  - **(proposed)** A usage or limit error is reported and the server keeps going.
  - **(proposed)** The server is fail-stop on an I/O error: it reports the error and exits with code 4, since after a failed fsync the on-disk state is unknown.
  - **(proposed)** The response to a write is sent only after the write is durable (R10).
- **R22 (proposed). Text encoding and grammar**, shared by the CLI and the server.
  - **Byte strings** are written as single tokens:
    - Bytes `0x21–0x7E` other than `\` and `"` are written as themselves.
    - `\` is written as `\\`, newline as `\n`, tab as `\t`.
    - Any other byte is written as `\xNN` (lowercase hex on output; either case accepted on input).
    - The empty byte string is written as `""`.
    - So a token never contains a space, a newline or a bare `"`.
  - **Commands:**
    - `get K`
    - `put K V`
    - `delete K`
    - `scan LO HI LIMIT`, where `HI` may be the reserved token `\inf` (unbounded)
    - `batch OP…`, where each OP is `put K V` or `delete K`
    - `check`
  - **Responses**, one line each:
    - `OK`
    - `VALUE V`
    - `NOTFOUND`
    - `PAIRS n K1 V1 … Kn Vn`
    - `LOG records=… bytes=… tail_ignored=…`
    - `ERR USAGE|LIMIT|CORRUPT|IO detail`
  - Tokens are separated by single spaces.
  - **Proven:** parsing a printed command or response gives back exactly the original, and decoding an encoded byte string gives back the same bytes. That is, `parse (print x) = x` for every x.
  - **Not promised:** the other direction, `print (parse s) = s`. It holds only for canonical input, because the parser also accepts uppercase hex.

## 6. Performance (benchmarked, not proven, unless noted)
- **R17.**
  - `get`/`put`/`delete` take O(log n) operations on the in-memory index.
  - `scan` takes O(log n + k) for k results.
  - **Proven:** the index's height is at most `c·log₂(n+1) + d` for n keys. The constants are fixed in the spec, and the balance invariant holds after every operation.
  - Wall-clock time is benchmarked. There is no operation-count cost model in v1.
- **R18.**
  - Writes inside one `batch` share a single fsync (group commit).
  - In server mode, consecutive writes may be grouped into one fsync only where this is *proven* to be equivalent to running them one at a time.
- **R19.** We'll publish a benchmark (ops/sec, p99 latency) against SQLite on the same machine. This is a goal, not a guarantee.

## 7. Testability: the deterministic fault and corruption harness
- **R23 (proposed).** v1 ships a deterministic harness that drives the real store code over a **simulated file system**. The simulated file system implements the same storage interface as the real one, with faults injected from a seed. Every run can be reproduced from its seed.
  - **Fault classes:**
    1. Crash after any write step. Bytes that were not fsynced are lost, kept, partly kept, or replaced with garbage.
    2. The log is truncated at every byte offset. This is exhaustive for small logs and seeded-random for large ones.
    3. Every single-bit flip, plus corrupted byte ranges in the middle of the log.
    4. Write or fsync returns an error.
  - **Oracle.** For every case, the harness computes the expected outcome *from the Lean spec*: which prefix of writes is visible, or "corrupt at offset p". It then compares that with what the store does on reopen, including the exit code.
  - A failure prints its seed and a minimal reproducing case.
  - **Mutation gate:** bugs injected on purpose must each be caught, for example skipping the checksum, not truncating after a torn tail, or acknowledging before fsync.
  - Real-process kill tests on the real file system (R10) remain as a secondary suite. Their random choices are logged so that failures can be replayed.

## 8. What will be proven vs. tested vs. trusted (expected)
| Requirement | Plan |
|---|---|
| R2–R9 | **Proven.** The fast index (a balanced tree) answers exactly like the sorted-list reference, for every sequence of operations. |
| R8 atomicity, R11/R12 (log format, replay, torn-tail vs. corruption classification) | **Proven** over a model of the log as a byte sequence. Examples: encoding valid records and appending any strict prefix of one more record recovers exactly those records; garbage before a valid record is reported as corrupt at the right offset. |
| R10/R11/R12 store logic (ack only after fsync, truncate a torn tail, block after an I/O error, refuse a corrupt log) | **Proven** against a model file system with crashes and injected I/O faults (`Spec/Store.lean`). The store is written once, generic over its file operations, and the proven code is the code that runs. *(Added 2026-11-21 with the user's approval.)* |
| R10/R11 (real files, fsync, OS) | **Tested** with the R23 harness, crash injection and differential tests against the model. This includes crash garbage the model leaves out (bytes that are not a prefix of anything written). **Trusted:** the filesystem, the OS and Lean's runtime. |
| R12 (checksums) | The checksum function is **proven** to match its spec. Detection is **proven** relative to the checksum. Collisions are an accepted risk. |
| R14/R15/R22 parsing and printing | Round-trip **proven**. Fuzzed. |
| R17 | Height bound **proven**. Wall-clock time benchmarked. |
| R19 | Benchmarked. |

## 9. Non-goals and parked items (v1)
**Parked:** wanted later, out of v1 until their prerequisites are ready.

| Item | Parked until |
|---|---|
| R13 Compaction (rewrite the log as a snapshot; contents unchanged) | The v1 core and recovery proofs are complete (Stage 4) and the R23 harness is green. It then needs a snapshot format and crash cases for atomic rename. |
| R16 HTTP interface | Phase 3 (hybrid non-Lean shell checked by differential tests). |
| Operation-count cost model (beyond the R17 height bound) | After v1 benchmarks show where the cost goes. |
| Repair tool for mid-log corruption | After compaction exists. |

**Accepted limitation: memory.** v1 has no separate cap on wire size or reply size.
- Request lines are bounded by R1 and R8a. Escaping can make a line up to about 4× its raw size, so roughly 256 MiB for a full batch.
- A `scan` reply is **not** bounded by those limits. It is bounded only by the store's size and the `limit` given.
- A reply-size cap can be added later if real workloads need it.

**Non-goals:**
- Multiple processes writing at once.
- More than one client per server process.
- Read-write transactions.
- Replication.
- Secondary indexes.
- Encryption.
- Windows-native builds (we develop on Linux/WSL).
