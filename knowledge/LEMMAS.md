# Reusable proven lemmas (index)

## LeanKV reference model: `LeanKVSol.Base.Properties` (namespace `LeanKV.Spec`)
Import `LeanKVSol.Base.*` in downstream apps, **not** `LeanKV.Spec.*` (that would clash with LeanKV's core).
- Order: `bytesLt_irrefl`, `bytesLt_trans`, `bytesLt_total`.
- Store: `Store.WellFormed`, `step_wellFormed`, `runFrom_empty_wellFormed`, `wellFormed_keys_nodup`.
- Lookup: `lookup_cons`, `lookup_insert_self`, `lookup_insert_ne`, `lookup_erase_self`, `lookup_erase_ne`, `erase_of_lookup_none`, `mem_of_lookup`, `lookup_of_mem`.
- Steps: `step_put`, `step_delete`, `get_eq`, `get_unchanged`, `put_then_get`, `put_other`, `delete_then_get`, `delete_other`, `delete_missing`, `limitError_unchanged`, `validBatch_single`, `validBatch_cons`, `batch_serial`, `batch_invalid`.
- Scan: `scan_sound`, `scan_complete`, `scan_sorted`, `scan_length_le`, `scan_limit_zero`, `scan_empty_range`.

## LeanKV implementation: `LeanKVImpl.Proofs.*` (namespace `LeanKV.Proofs`)
`import LeanKVImpl.Proofs` brings in all of these. They are **implementation-side only**: a spec package imports `LeanKVSol.Base.*` and cannot see them. Keep the spec on `List UInt8` (`Bytes`) and `Nat`, prove spec codecs in the spec itself (as `decodeU64_u64le` does), and bridge to `ByteArray` in `impl/` with the lemmas below. There is no standalone bytes library yet; these lemmas live in LeanKV (file in parentheses, under `examples/kvstore/impl/LeanKVImpl/Proofs/`).
- Bytes (`Bytes.lean`): `toBytes_eq`, `toBytes_length`, `toBytes_inj`, `toBytes_ofBytes`, `ofBytes_toBytes`, `toBytes_getElem`, `toList_loop` (`ByteArray.toList.loop` = reverse-accumulator ++ `drop`; the "array loop ≡ list" bridge).
- Builders (`Recover.lean`): `toBytes_push` (`toBytes (a.push x) = toBytes a ++ [x]`), `toBytes_append`, `toBytes_extract`, `getElem!_toBytes`. (`Encode.lean` has primed duplicates `toBytes_push'`, `toBytes_append'`; use the unprimed ones.)
- Builder loops (`Encode.lean`): `toBytes_pushU32` (`Core.pushU32` = `++ u32le n`), `toBytes_foldl_pushOp` (a `foldl` of pushes into a `ByteArray` = list `flatMap`; the pattern for "builder ≡ list concatenation").
- Slices (`Line.lean`): `toBytes_extract_self` (empty slice), `toBytes_extract_succ` (extending a slice by one byte).
- Comparison (`Compare.lean`): `drop_toBytes_cons`, `drop_toBytes_nil`, `cmpBytes_spec`, `ltBytes_spec`.
- Index, on any well-formed `Tree` (`Tree.lean`, `Scan.lean`, `Step.lean`): `toList_lookup` (`Core.lookup` = spec lookup), `toList_insert`, `toList_erase`, `scanAux_spec`, `step_spec`.
- **Substrate** (`Substrate.lean`): `runPick`, `PickOk`, `execPick_spec`, **`substrate_crash_consistent`**, **`substrate_no_faults`**. For any app with `PickOk pickI pick`, sessions answer like `runPick pick` and are crash-consistent.
- **App level** (`Substrate.lean`): `Refines dec mstep pick`, `logState_wellFormed`, `runPick_wellFormed`, `runPick_model`, `AppOutcome`, **`app_crash_consistent`** (from `PickOk` and `Refines`: after any crash the log decodes to the app model after the acknowledged commands, possibly plus one). Each app instantiates it as `<App>Impl.crash_consistent`.
- Store sessions (`Session.lean`): `open_spec`, `exec_spec`, `Good`, `Clean`, `clean_crash`, `inflight_crash`.
- Log format (`Canon.lean`): `recover_ok_canon`, `recover_prefix`, `decodeRecord_canon`, `readRecords_canon`.

## Worked example: `examples/counter/`
- `Counter.Spec.decodeU64_u64le` (8-byte little-endian codec round trip), `pickRef_refines` (refinement of an app model by its KV translation), `reachable_bounded` (an invariant from the empty state), `CounterImpl.countOf_eq`, `CounterImpl.pick_ok`, `CounterImpl.crash_consistent`.

## Exit-test app: `examples/ledger/`
- Sorted-list state with a total; `plan` (the rules, taking a balance lookup); `kvRun_refines` (multi-step refinement); `reachable_good`, `reachable_total` (invariants from the empty ledger); `LedgerImpl.look_eq`, `LedgerImpl.crash_consistent`.
