# LeanKV — Trust manifest (Stage 6)

What each requirement in [REQUIREMENTS.md](REQUIREMENTS.md) rests on: **proven** (a Lean theorem, kernel-checked), **tested** (a named test suite), or **trusted** (assumed, with the reason). Every claim below is re-checked by one command:

```
examples/kvstore/tools/audit.sh        # the CI gate; prints AUDIT PASSED
```

## How the guarantee is established

| Step | What it checks |
|---|---|
| Frozen spec | `spec.lock` (spec v2, signed off 2026-11-21) pins the exact spec files the user approved. `tools/check_lock.sh` fails on any change. v1 was superseded because it could never pass the comparator; see `spec.lock.v1` and FRICTION.md. |
| Spec gates | Every spec declaration has an `English:` doc. No spec definition calls an implementation hole. Every worked example from the requirements holds (`#guard`). |
| Spec-level proofs | The 124 theorems about the spec itself (R1–R8 properties of the reference model, the wire format round-trips, the log format) are proven. Only the 9 implementation obligations are open in the spec (`tools/SpecAxioms.lean`). |
| External verifier | `lake comparator`, sandboxed, with `--paranoid` (re-checked by every external kernel bundled with Lean), **accepts all 9 obligations** for the implementation. It confirms the statements and every definition they depend on are exactly the frozen ones, and that only `propext`, `Quot.sound`, `Classical.choice` are used. (`impl/tools/judge.sh`) |
| Verified-module audit | On the compiled code of the core, proofs and solution: 373 theorems use only the 3 permitted axioms; no `sorry`, `unsafe`, `partial`, `opaque`, `implemented_by` or `extern`; the trusted shell is not imported by any verified module (`impl/audit/AuditVerified.lean`; a negative test with planted violations confirmed each check fires). |
| Anti-cheating regression | `tests/comparator-smoke/run.sh`: the comparator accepts an honest solution and rejects `sorry`, a custom axiom, a weakened statement and a redefined spec (5/5). |

## Requirement by requirement

| Req | Status | Evidence |
|---|---|---|
| R1 size limits | **Proven** | `invalid_key_rejected`, `invalid_value_rejected`, `limitError_unchanged` (reference model); `impl_run_eq` (the implementation answers exactly as the model). |
| R2 key order | **Proven** | `bytesLt_irrefl`, `bytesLt_trans`, `bytesLt_total`; the implementation's byte comparison equals it (`cmpBytes_spec`, inside `impl_run_eq`). |
| R3 one value per key | **Proven** | `wellFormed_keys_nodup`, `runFrom_empty_wellFormed`; `impl_toList_eq` (the index holds exactly the reference store). |
| R4–R6 get, put, delete | **Proven** | `get_unchanged`, `put_then_get`, `put_other`, `delete_then_get`, `delete_other`, `delete_missing`; `impl_run_eq`. |
| R7, R7a scan | **Proven** | `scan_length_le`, `scan_sorted`, `scan_sound`, `scan_complete` (returns the *first* `limit` in-range pairs), `scan_limit_zero`, `scan_empty_range`, `scan_ok`; `impl_run_eq` (including the pruning, early-stopping scan). |
| R8, R8a batch atomicity and limits | **Proven** | `batch_invalid`, `batch_serial` (a batch equals its writes run one at a time); `impl_run_eq`. On disk: one record per batch, so a torn batch is never visible (`recover_torn_tail`, `store_crash_consistent`). |
| R9 determinism | **Proven** | The reference `run` is a function of the commands; `impl_run_eq`. |
| R10 persistence | **Proven** on the model file system; **tested** on real files; **trusted:** fsync | `store_crash_consistent`, `store_no_faults` (an acknowledged write survives any crash). Tested: R23 harness, real-file self-test, kill tests. Trusted: that the OS honours `fsync`. Kill tests cannot exercise power loss. |
| R11 crash consistency | **Proven** on the model file system; **tested** beyond it | `store_crash_consistent`: under any fault script and any crash, the reopened log stands for exactly the acknowledged writes, plus possibly the one in flight, applied in full. After an I/O error the store answers `ERR IO` to everything. Tested: garbage crashes and multi-session chains (R23), SIGKILL (kill tests). |
| R12 corruption detection | **Proven** relative to the checksum; collisions **accepted risk** | `recover_corrupt` (a bad record followed by a valid one is refused at its offset), `recover_torn_tail` (a torn write is ignored, *whatever the stored data*, thanks to byte stuffing and `magic_only_at_start`), `recover_after_truncate`, `store_refuses_corrupt` (refused without touching the disk), `impl_recover_eq` (the `ByteArray` recovery equals the spec's for *every* file content). Tested: every bit flip in mid-log records is refused, flips in the last record drop it (R23). Accepted: CRC-32C + magic collisions (about 2⁻⁶⁴ per offset); bit rot in the last record looks like a torn write. |
| R13 compaction | Parked | Not in v1 (REQUIREMENTS §9). |
| R14 CLI and exit codes | **Proven** (table, parsing); **tested** (binary) | `Reply.exitCode` is the single exit-code table; parsing proven (R22). The `leankv` binary was exercised on every requirement example. |
| R15 server mode | **Proven** parsing and framing; **tested** | `printed_no_newline` (one line per reply). Fail-stop on I/O error, continue on usage errors: shell code, tested manually and by the kill tests. |
| R16 HTTP | Parked | Phase 3. |
| R17 complexity | Height **proven**; wall-clock **benchmarked** (Stage 7) | `impl_height_le`: tree height ≤ 3·⌊log₂(n+1)⌋+2 (the AVL proof gives ≤ 2·⌊log₂(n+1)⌋+1). Known gap: the shape is proven, not how operations use it. Benchmarks are Stage 7. |
| R18 group commit | Batch-level only | A batch is one record with one fsync (`batch_serial` licenses it). Cross-command grouping in server mode is not implemented. Doing it would need a spec change (the store contract is per-command). |
| R19 benchmark vs SQLite | Not yet | Stage 7. |
| R20 library interface | **Proven** components | The reference model, recovery, parser/printer and exit codes are spec functions; the store is the proven core. |
| R21 `check` | **Proven** | `storeCheck_spec`: `check` never modifies the disk and reports exactly the spec's recovery outcome. |
| R22 text encoding | **Proven** | `decodeBytes_encodeBytes`, `parseRequest_printRequest`, `parseReply_printReply`, `encodeBytes_visible`, `printed_no_newline`. |
| R23 fault harness | **Done** | `impl/LeanKVImpl/Test/Harness.lean`: 150 seeds of chained sessions with faults, prefix and garbage crashes and bit flips, judged against the spec. The mutation gate catches all 4 planted bugs (ack before fsync, no torn-tail truncation, continuing after an I/O error, opening a corrupt log). |

## The trusted base (not proven)

| Component | Why it is trusted | How it is checked |
|---|---|---|
| The model file system's crash semantics (`Spec/Store.lean`) | It is the assumption the crash proofs rest on: a crash keeps a prefix of the durable or the current version. It was reviewed and signed off as part of the spec. | Garbage crashes go beyond it in the R23 harness. |
| C leaf `impl/c/lkv_io.c` (open + lock + directory fsync, read, append, fsync, ftruncate, close; about 90 lines) | Lean 4.36 has no `fsync` and cannot truncate at an offset. | Real-file self-test (the real store vs the reference model, thousands of commands across sessions), kill tests. |
| Shell `impl/LeanKVImpl/Shell/` (argument handling, stdin/stdout, the serve loop; uses one `partial def`) | Glue around proven functions. | Requirement examples run on the binary, kill tests. |
| Linux, the file system, `fsync` semantics | Outside Lean. | Power loss is **not** tested. Integrating a fault-injecting file system (LazyFS or dm-flakey) is a recorded follow-up. |
| The Lean compiler, runtime and C toolchain | The running binary is compiled code; proofs are about the Lean definitions. | `--paranoid` re-checks the proofs with independent kernels; the binary is exercised by the real-file and kill tests. |
| `lake comparator` and the Lean kernel | The judge. | Anti-cheating regression test (5/5), and the `--paranoid` external kernels. |

## Accepted risks and known gaps

- **Checksum collisions:** random bytes pass as a valid record with probability about 2⁻⁶⁴ per offset. A false accept or a false refusal is possible in principle.
- **Last-record bit rot:** a bit flip in the last acknowledged record is indistinguishable from a torn write, so the record is dropped without an error (REQUIREMENTS R12).
- **Power loss** is covered by proof against the model file system, not by a real power-loss test.
- **Complexity:** the tree's balance is proven; whether each operation actually runs in O(log n) is benchmarked, not proven.
- **Performance shortcuts still owed proofs (Stage 7):** a table-driven CRC and a direct `ByteArray` encoder. v1 uses the spec's own bitwise CRC and encoder.
