import LeanKVImpl.Proofs.Compare
import LeanKVImpl.Core.Log

/-! Proof licence for the fast CRC (Stage 7): it computes exactly the spec's CRC-32C. -/

namespace LeanKV.Proofs
open LeanKV.Spec

theorem crcByteFast_eq (c : UInt32) (b : UInt8) : Core.crcByteFast c b = crc32cByte c b := rfl

theorem crcLoop_eq (b : ByteArray) : ∀ (i : Nat) (c : UInt32),
    Core.crcLoop b i c = ((toBytes b).drop i).foldl crc32cByte c := by
  intro i c
  induction h : b.size - i generalizing i c with
  | zero =>
    rw [Core.crcLoop, dif_neg (by omega), drop_toBytes_nil b i (by omega)]; rfl
  | succ n ih =>
    rw [Core.crcLoop, dif_pos (by omega), drop_toBytes_cons b i (by omega), List.foldl_cons,
      ih (i + 1) _ (by omega), crcByteFast_eq]

theorem crc32cBA_eq (b : ByteArray) : Core.crc32cBA b = crc32c (toBytes b) := by
  rw [Core.crc32cBA, crcLoop_eq, List.drop_zero]; rfl

end LeanKV.Proofs
