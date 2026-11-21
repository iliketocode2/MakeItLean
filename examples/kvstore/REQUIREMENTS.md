# LeanKV — Requirements (Stage 0, DRAFT for approval)

> Stage 0 of the MakeItLean workflow (see `docs/PLAN.md`). Everything here is plain English. Once you approve it, Stage 1 turns it into a Lean spec. Each requirement has an ID that the spec will cite.
> Items marked **[DECIDE]** need your call.

## 1. What it is
LeanKV is a single-process, persistent, ordered key-value store. It is used through a command-line tool and a simple line-based server mode. The aims are to be simple enough to prove and fast enough to be worth benchmarking.

## 2. Data model
- **R1. Keys and values are byte strings.**
  - A key is 1–1024 bytes. A value is 0–1 MiB.
  - Anything outside these limits is rejected with an error, and nothing changes.
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

- **R9. Determinism.** The answer to every operation depends only on the operations that came before it. "Real" behaviour is defined as: apply each operation in order to a simple sorted list of pairs.

## 4. Durability
- **R10. Persistence.** Once a write (`put`, `delete` or `batch`) reports success, its effect survives a process crash or kill and is visible after restart.
- **R11. Crash consistency.** After a crash at *any* moment, including halfway through writing a batch, the reopened store equals the result of some prefix of the successful writes, plus possibly the one in flight, applied in full or not at all. Partial batches are never visible.
- **R12. Corruption detection.** If the log ends in a torn or garbage record, recovery ignores it and everything after it. If a corrupted record appears *before* valid ones, the store refuses to open and reports where the corruption is. **[DECIDE]** Alternatively it could truncate there and open.
- **R13. Compaction** (stretch goal for v1). `compact` rewrites the log as a snapshot. The visible contents are identical before and after compaction.

## 5. Interface
- **R14. CLI:** `leankv <dbdir> get|put|delete|scan|batch|compact …`. Exit code 0 on success, 1 on "not found", 2 on a usage or limit error, 3 on corruption.
- **R15. Server mode:** `leankv <dbdir> serve` reads one command per line on stdin and writes one response per line on stdout. Benchmarks drive this mode.
- **R16.** HTTP interface. **[DECIDE]** Leave it out of v1, since it would add the hybrid shell, which is better saved for Phase 3. Or include it as a thin layer?

## 6. Performance (benchmarked, not proven, unless noted)
- **R17.**
  - `get`/`put`/`delete` take O(log n) operations on the in-memory index.
  - `scan` takes O(log n + k) for k results.
  - **[DECIDE]** Should these be *proven* with an explicit operation-count cost model (DeepMind style), or only benchmarked?
- **R18.**
  - Writes inside one `batch` share a single fsync (group commit).
  - In server mode, consecutive writes may be grouped into one fsync only where this is *proven* to be equivalent to running them one at a time.
- **R19.** We'll publish a benchmark (ops/sec, p99 latency) against SQLite on the same machine. This is a goal, not a guarantee.

## 7. What will be proven vs. tested vs. trusted (expected)
| Requirement | Plan |
|---|---|
| R2–R9 | **Proven.** The fast index (a balanced tree) answers exactly like the sorted-list reference, for every sequence of operations. |
| R8 atomicity, R11 (log format and replay logic) | **Proven** over a model of the log as a byte sequence: `replay (encode ops ++ garbage) = apply (prefix of ops)`. |
| R10/R11 (real files, fsync, OS) | **Tested** with crash injection (kill at random points, then reopen and compare to the model) and differential tests against the model. **Trusted:** the filesystem, the OS and Lean's runtime. |
| R12 (checksums) | The checksum function is **proven** to match its spec. Detection is **proven** relative to the checksum. Collisions are an accepted risk. |
| R14/R15 parsing | Command parser **proven** to round-trip with the printer. Fuzzed. |
| R17/R19 | Benchmarked. R17 can be proven if you choose so above. |

## 8. Non-goals (v1)
- Multiple processes writing at once.
- Read-write transactions.
- Replication.
- Secondary indexes.
- Encryption.
- Windows-native builds (we develop on Linux/WSL).
