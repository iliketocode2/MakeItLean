import LeanKVSol.Base.Bytes

/-! Foundations: `ByteArray` as the spec's byte list (Stage 4). -/

namespace LeanKV.Proofs
open LeanKV.Spec

theorem toList_loop (bs : ByteArray) (i : Nat) (r : List UInt8) :
    ByteArray.toList.loop bs i r = r.reverse ++ bs.data.toList.drop i := by
  induction h : bs.size - i generalizing i r with
  | zero =>
    rw [ByteArray.toList.loop]
    have : ¬ i < bs.size := by omega
    simp only [this, ↓reduceIte]
    have : bs.data.toList.drop i = [] := by simp [List.drop_eq_nil_iff, ByteArray.size_data] at *; omega
    simp [this]
  | succ n ih =>
    rw [ByteArray.toList.loop]
    have hi : i < bs.size := by omega
    simp only [hi, ↓reduceIte]
    rw [ih (i + 1) _ (by omega)]
    rw [List.drop_eq_getElem_cons (i := i) (by simp [ByteArray.size_data]; exact hi)]
    have hd : i < bs.data.size := by simp [ByteArray.size_data]; exact hi
    obtain ⟨d⟩ := bs
    simp [ByteArray.get!, getElem!_pos d i hd]

theorem toBytes_eq (b : ByteArray) : toBytes b = b.data.toList := by
  simp [toBytes, ByteArray.toList, toList_loop]

theorem toBytes_length (b : ByteArray) : (toBytes b).length = b.size := by
  simp [toBytes_eq, ByteArray.size_data]

theorem toBytes_inj {a b : ByteArray} (h : toBytes a = toBytes b) : a = b := by
  rw [toBytes_eq, toBytes_eq] at h
  exact ByteArray.ext (Array.toList_inj.mp h)

theorem toBytes_ofBytes (l : Bytes) : toBytes (ofBytes l) = l := by
  simp [toBytes_eq, ofBytes]

theorem ofBytes_toBytes (b : ByteArray) : ofBytes (toBytes b) = b := by
  apply toBytes_inj; rw [toBytes_ofBytes]

theorem toBytes_getElem (b : ByteArray) (i : Nat) (h : i < b.size) :
    (toBytes b)[i]'(by rw [toBytes_length]; exact h) = b[i] := by
  simp [toBytes_eq, ByteArray.getElem_eq_getElem_data]

end LeanKV.Proofs
