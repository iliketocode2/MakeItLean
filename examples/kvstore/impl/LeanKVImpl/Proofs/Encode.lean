import LeanKVImpl.Proofs.Crc

/-! `impl_encodeRecord_eq`: the direct `ByteArray` encoder writes exactly the spec's bytes (Stage 7). -/

set_option linter.deprecated false

namespace LeanKV.Proofs
open LeanKV.Spec

theorem toBytes_push' (a : ByteArray) (x : UInt8) : toBytes (a.push x) = toBytes a ++ [x] := by
  simp [toBytes_eq, ByteArray.data_push]

theorem toBytes_append' (a b : ByteArray) : toBytes (a ++ b) = toBytes a ++ toBytes b := by
  simp [toBytes_eq, ByteArray.data_append]

theorem toBytes_pushU32 (out : ByteArray) (n : Nat) :
    toBytes (Core.pushU32 out n) = toBytes out ++ u32le n := by
  simp [Core.pushU32, toBytes_push', u32le]

theorem toBytes_pushOp (out : ByteArray) (op : WriteOp ByteArray) :
    toBytes (Core.pushOp out op) = toBytes out ++ encodeOp (op.map toBytes) := by
  cases op <;> simp [Core.pushOp, WriteOp.map, encodeOp, toBytes_pushU32, toBytes_append',
    toBytes_push', toBytes_length]

theorem toBytes_foldl_pushOp : ∀ (ops : List (WriteOp ByteArray)) (out : ByteArray),
    toBytes (ops.foldl Core.pushOp out) = toBytes out ++ (ops.map (WriteOp.map toBytes)).flatMap encodeOp
  | [], out => by simp
  | op :: ops, out => by
    rw [List.foldl_cons, toBytes_foldl_pushOp ops, toBytes_pushOp]; simp

theorem toBytes_encodePayloadBA (ops : List (WriteOp ByteArray)) :
    toBytes (Core.encodePayloadBA ops) = encodePayload (ops.map (WriteOp.map toBytes)) := by
  have e : toBytes ByteArray.empty = [] := by simp [toBytes_eq]
  simp [Core.encodePayloadBA, toBytes_foldl_pushOp, toBytes_pushU32, encodePayload, e]

theorem toBytes_stuffInto (src : ByteArray) : ∀ (i : Nat) (out : ByteArray),
    toBytes (Core.stuffInto src i out) = toBytes out ++ stuff ((toBytes src).drop i) := by
  intro i out
  induction h : src.size - i generalizing i out with
  | zero =>
    rw [Core.stuffInto, dif_neg (by omega), drop_toBytes_nil src i (by omega)]; simp [stuff]
  | succ n ih =>
    rw [Core.stuffInto, dif_pos (by omega), ih (i + 1) _ (by omega), drop_toBytes_cons src i (by omega)]
    by_cases hx : src[i] = 0xC7
    · simp [hx, toBytes_push', stuff, stuffByte]
    · simp [hx, toBytes_push', stuff, stuffByte]

/-- `impl_encodeRecord_eq` for the direct encoder. -/
theorem core_encodeRecord_eq (ops : List (WriteOp ByteArray)) :
    toBytes (Core.encodeRecord ops) = encodeRecord (ops.map (WriteOp.map toBytes)) := by
  have e : toBytes ByteArray.empty = [] := by simp [toBytes_eq]
  have hm : toBytes ⟨#[0xC7, 0x4B, 0x56, 0x31]⟩ = magic := by simp [toBytes_eq, magic]
  simp only [Core.encodeRecord, toBytes_stuffInto, List.drop_zero, hm, encodeRecord, recordBody,
    toBytes_pushU32, toBytes_append', crc32cBA_eq, toBytes_encodePayloadBA, e, List.nil_append,
    ← toBytes_length]

end LeanKV.Proofs
