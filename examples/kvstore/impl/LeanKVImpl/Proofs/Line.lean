import LeanKVImpl.Proofs.Recover
import LeanKVImpl.Core.Line

/-! Proof licence for the iterative line splitter (Stage 7). -/

set_option linter.deprecated false

namespace LeanKV.Proofs
open LeanKV.Spec

/-- Glue a partial token onto the first piece of a split. -/
def glue (cur : Bytes) : List Bytes → List Bytes
  | [] => [cur]
  | t :: ts => (cur ++ t) :: ts

theorem splitSpaces_cons (b : UInt8) (r : Bytes) :
    splitSpaces (b :: r) = if b == 0x20 then [] :: splitSpaces r else glue [b] (splitSpaces r) := by
  conv => lhs; unfold splitSpaces
  cases h : splitSpaces r with
  | nil => exact absurd h (splitSpaces_ne_nil r)
  | cons t ts => by_cases hb : b = 0x20 <;> simp [hb, glue]

theorem toBytes_extract_self (l : ByteArray) (j : Nat) : toBytes (l.extract j j) = [] := by
  rw [toBytes_extract]; simp

theorem glue_nil {ts : List Bytes} (h : ts ≠ []) : glue [] ts = ts := by
  cases ts <;> simp_all [glue]

theorem glue_glue (a b : Bytes) (ts : List Bytes) : glue a (glue b ts) = glue (a ++ b) ts := by
  cases ts <;> simp [glue]

theorem toBytes_extract_succ (l : ByteArray) {s i : Nat} (hs : s ≤ i) (hi : i < l.size) :
    toBytes (l.extract s (i + 1)) = toBytes (l.extract s i) ++ [l[i]] := by
  rw [toBytes_extract, toBytes_extract, show i + 1 - s = (i - s) + 1 by omega, List.take_succ]
  congr 1
  rw [List.getElem?_drop, show s + (i - s) = i by omega]
  simp [toBytes_length, hi, toBytes_getElem]

theorem splitBA_spec (l : ByteArray) : ∀ (i s : Nat) (acc : Array Bytes), s ≤ i → i ≤ l.size →
    Core.splitBA l i s acc = acc.toList ++ glue (toBytes (l.extract s i)) (splitSpaces ((toBytes l).drop i)) := by
  intro i s acc hs hi
  induction h : l.size - i generalizing i s acc with
  | zero =>
    have : i = l.size := by omega
    subst this
    rw [Core.splitBA, dif_neg (by omega), drop_toBytes_nil l l.size (by omega)]
    simp [splitSpaces, glue]
  | succ n ih =>
    rw [Core.splitBA, dif_pos (by omega), drop_toBytes_cons l i (by omega), splitSpaces_cons]
    by_cases hsp : l[i] = 0x20
    · simp only [hsp, beq_self_eq_true, ↓reduceIte]
      rw [ih (i + 1) (i + 1) _ (by omega) (by omega) (by omega), toBytes_extract_self,
        glue_nil (splitSpaces_ne_nil _)]
      simp [glue]
    · simp only [show (l[i] == 0x20) = false by simpa using hsp, Bool.false_eq_true, ↓reduceIte]
      rw [ih (i + 1) s acc (by omega) (by omega) (by omega), glue_glue, toBytes_extract_succ l hs (by omega)]

/-- The iterative splitter is the spec's `splitSpaces`. -/
theorem splitBA_eq (l : ByteArray) : Core.splitBA l 0 0 #[] = splitSpaces (toBytes l) := by
  rw [splitBA_spec l 0 0 #[] (Nat.le_refl _) (Nat.zero_le _)]
  rw [toBytes_extract_self, List.drop_zero, glue_nil (splitSpaces_ne_nil _)]
  simp

/-- `parseLine` is exactly the spec's parser. -/
theorem parseLine_eq (l : ByteArray) : Core.parseLine l = parseRequest (toBytes l) := by
  simp only [Core.parseLine, parseRequest, tokenize, splitBA_eq]
  split <;> rfl

end LeanKV.Proofs
