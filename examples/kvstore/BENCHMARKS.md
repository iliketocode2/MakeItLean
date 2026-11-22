# LeanKV — Benchmarks (R19, Stage 7)

**Machine:** Intel Core Ultra 9 288V, 8 cores, WSL2 Ubuntu 24.04, ext4 on a virtual disk. **Date:** 2026-11-21.
**Reproduce:** `examples/kvstore/impl/bench/bench.py` (end to end) and `impl/.lake/build/bin/leankv-bench` (in-process).

## Setup, and why it is not perfectly fair

- **LeanKV** runs as `leankv serve`, driven over a pipe by a Python process. Every operation pays a process round trip and the text protocol (escaping, parsing).
- **SQLite 3.45** runs in-process from Python (`journal_mode=WAL`, `synchronous=FULL`, one transaction per durable write). It pays no inter-process cost. **This favours SQLite**, especially for reads.
- Both fsync every acknowledged write. Request lines are built before timing, so only the stores' round trips are timed.
- WSL's fsync timing is noisy. The ranges below come from repeated runs, and p99 write latencies vary by 2–4× between runs.

## End to end (51,000 keys, 100-byte values)

| Workload | LeanKV (pipe) | SQLite (in-process) | Reading |
|---|---|---|---|
| Durable `put` | 270–440 ops/s, p50 2.2–2.8 ms | 380–430 ops/s, p50 2.4–2.6 ms | **Even.** Both are fsync-bound. |
| Durable batch of 100 puts | 26–28k writes/s, p50 3.2–3.6 ms | 34k writes/s, p50 1.9–2.0 ms | LeanKV within ~20%, despite the pipe and text protocol. |
| Bulk load (batches of 100) | 27–29k keys/s | 62–87k keys/s | SQLite 2–3× faster. LeanKV's cost is in parsing and the CRC (below). |
| `get` (random) | 14k ops/s, p50 ~50 µs | 170–300k ops/s, p50 3 µs | Not comparable: LeanKV's number is mostly the pipe round trip (see in-process). |
| `scan` 10 pairs | 8–9k ops/s, p50 ~100 µs | 84–160k ops/s, p50 6 µs | Same caveat. |
| Reopen (51k keys) | 155–205 ms | 0.3 ms | **Design difference.** LeanKV replays its whole log into memory; SQLite keeps an on-disk B-tree. Compaction (R13, parked) would bound this. |

## In-process (the store itself, no pipe)

| Operation (50k keys) | Time |
|---|---|
| `get` | 0.58 µs |
| `scan` 10 pairs | 0.96 µs |
| `put` (index only) | 1.2 µs |
| Encode a 100-put batch record (12.5 KB) | 229 µs, of which CRC-32C 113 µs |
| Decode one such record | 145 µs |
| Recover a 6 MB log (500 records) | 78 ms |
| Parse a 100-put batch line | 180 µs |

The core's index operations are sub-microsecond. That is competitive with SQLite's in-process reads (about 3 µs including Python). End-to-end read numbers mostly measure the pipe.

## Stage 7 optimizations (each landed only with a proof)

| Change | Before → after | Proof |
|---|---|---|
| CRC-32C: the spec's 8 bit-steps written out, run directly on the array (no list per byte, no array→list conversion) | 423 → 113 µs per 12.5 KB | `crcByteFast_eq` (by `rfl`), `crc32cBA_eq` |
| Records built directly in a `ByteArray` instead of through spec lists | 1,142 → 229 µs per 100-put record | `core_encodeRecord_eq` (now the `impl_encodeRecord_eq` obligation) |
| Tail-recursive unstuffing and record reading | Recovery of a 60 MB record: **stack overflow → works**; 6 MB recovery 233 → 78 ms | `unstuffAt_spec`, `readFrom_spec` (generalized over accumulators) |
| Iterative request-line splitting (`parseLine`) | A valid 60 MB batch line: **stack overflow → works**; that batch 11 s → 3.3 s end to end | `parseLine_eq`: equal to the spec's `parseRequest` for every line |

The comparator still accepts all 9 obligations after every change (`tools/audit.sh`).

## Found while benchmarking: a robustness bug the proofs could not see

A batch at the R8a limits (10,000 writes, about 60 MB of text) crashed `serve` with a **stack overflow**. The spec's list-based parser and the core's unstuffing both recursed once per byte. Nothing was acknowledged and the log stayed intact, so durability held, but valid input took the server down. **The proofs are about results, not about stack depth.** It is fixed by the last two rows above, and `impl/tests/limits_test.sh` now runs the R1/R8a maxima end to end in CI.

**CLI limit:** Linux caps a single command-line argument at 128 KB, so values larger than that must go through `serve` (or a future stdin option).

## Next optimizations (each needs a proof)

- **Table-driven CRC.** It needs a hand-written GF(2)-linearity proof, because `bv_decide` relies on a non-whitelisted axiom. It would roughly halve encode time.
- **`ByteArray` token decoding.** It needs a proof that it equals the spec's `decodeBytes`/`parseRequestTokens` on all inputs. It would cut bulk-load parsing.
- **Compaction / snapshots (R13, parked).** These would bound reopen time.
- **Cross-command group commit in server mode (R18).** This needs a spec change, because the store contract is per command.
