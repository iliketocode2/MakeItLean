# Reusable proven lemmas (index)

## LeanKV reference model: `LeanKVSol.Base.Properties` (namespace `LeanKV.Spec`)
Import `LeanKVSol.Base.*` in downstream apps, **not** `LeanKV.Spec.*` (that would clash with LeanKV's core).
- Order: `bytesLt_irrefl`, `bytesLt_trans`, `bytesLt_total`.
- Store: `Store.WellFormed`, `step_wellFormed`, `runFrom_empty_wellFormed`, `wellFormed_keys_nodup`.
- Lookup: `lookup_cons`, `lookup_insert_self`, `lookup_insert_ne`, `lookup_erase_self`, `lookup_erase_ne`, `erase_of_lookup_none`, `mem_of_lookup`, `lookup_of_mem`.
- Steps: `step_put`, `step_delete`, `get_eq`, `get_unchanged`, `put_then_get`, `put_other`, `delete_then_get`, `delete_other`, `delete_missing`, `limitError_unchanged`, `validBatch_single`, `validBatch_cons`, `batch_serial`, `batch_invalid`.
- Scan: `scan_sound`, `scan_complete`, `scan_sorted`, `scan_length_le`, `scan_limit_zero`, `scan_empty_range`.

## LeanKV implementation: `LeanKVImpl.Proofs.*` (namespace `LeanKV.Proofs`)
- Bytes: `toBytes_eq`, `toBytes_length`, `toBytes_inj`, `toBytes_ofBytes`, `ofBytes_toBytes`, `toBytes_getElem`, `toBytes_push`, `toBytes_append`, `toBytes_extract`, `drop_toBytes_cons`, `drop_toBytes_nil`, `getElem!_toBytes`.
- Index (on any well-formed `Tree`): `toList_lookup` (`Core.lookup` = spec lookup), `toList_insert`, `toList_erase`, `scanAux_spec`, `step_spec`, `cmpBytes_spec`, `ltBytes_spec`.
- **Substrate** (`Proofs/Substrate.lean`): `runPick`, `PickOk`, `execPick_spec`, **`substrate_crash_consistent`**, **`substrate_no_faults`**. For any app with `PickOk pickI pick`, sessions answer like `runPick pick` and are crash-consistent.
- Store sessions: `open_spec`, `exec_spec`, `Good`, `Clean`, `clean_crash`, `inflight_crash`.
- Log format: `recover_ok_canon`, `recover_prefix`, `decodeRecord_canon`, `readRecords_canon`.

## Worked example: `examples/counter/`
- `Counter.Spec.decodeU64_u64le` (8-byte little-endian codec round trip), `pickRef_refines` (refinement of an app model by its KV translation), `CounterImpl.countOf_eq`, `CounterImpl.pick_ok`.
