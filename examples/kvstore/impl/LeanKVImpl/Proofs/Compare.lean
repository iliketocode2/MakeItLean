import LeanKVImpl.Proofs.Bytes
import LeanKVImpl.Core.Index
import LeanKV.Spec.Properties

/-! `cmpBytes` agrees with the spec's key order `bytesLt` (Stage 4). -/

set_option linter.deprecated false

namespace LeanKV.Proofs
open LeanKV.Spec LeanKV.Core

/-- Three-way comparison on spec byte lists. -/
def cmpL : Bytes → Bytes → Ordering
  | [], [] => .eq
  | [], _ :: _ => .lt
  | _ :: _, [] => .gt
  | x :: xs, y :: ys => if x < y then .lt else if y < x then .gt else cmpL xs ys

theorem cmpL_spec (a b : Bytes) :
    cmpL a b = if bytesLt a b then .lt else if a = b then .eq else .gt := by
  induction a generalizing b with
  | nil => cases b <;> simp [cmpL, bytesLt]
  | cons x xs ih =>
    cases b with
    | nil => simp [cmpL, bytesLt]
    | cons y ys =>
      simp only [cmpL, bytesLt, ih]
      by_cases h1 : x < y
      · simp [h1]
      · by_cases h2 : y < x
        · have : x ≠ y := fun e => by subst e; exact h1 h2
          simp [h1, h2, this]
        · have : x = y := by
            rcases UInt8.lt_or_lt_of_ne (a := x) (b := y) |> fun f => (Classical.em (x = y)) with e | e
            · exact e
            · rcases UInt8.lt_or_lt_of_ne e with h | h
              · exact absurd h h1
              · exact absurd h h2
          subst this
          simp [h1]

theorem drop_toBytes_cons (a : ByteArray) (i : Nat) (h : i < a.size) :
    (toBytes a).drop i = a[i] :: (toBytes a).drop (i + 1) := by
  rw [List.drop_eq_getElem_cons (by rw [toBytes_length]; exact h), toBytes_getElem]

theorem drop_toBytes_nil (a : ByteArray) (i : Nat) (h : ¬ i < a.size) : (toBytes a).drop i = [] := by
  simp [List.drop_eq_nil_iff, toBytes_length]; omega

theorem cmpFrom_eq (a b : ByteArray) (i : Nat) :
    cmpFrom a b i = cmpL ((toBytes a).drop i) ((toBytes b).drop i) := by
  induction h : a.size - i generalizing i with
  | zero =>
    rw [cmpFrom]
    have ha : ¬ i < a.size := by omega
    rw [dif_neg ha, drop_toBytes_nil a i ha]
    by_cases hb : i < b.size
    · rw [if_pos hb, drop_toBytes_cons b i hb]; rfl
    · rw [if_neg hb, drop_toBytes_nil b i hb]; rfl
  | succ n ih =>
    rw [cmpFrom]
    have ha : i < a.size := by omega
    rw [dif_pos ha, drop_toBytes_cons a i ha]
    by_cases hb : i < b.size
    · rw [dif_pos hb, drop_toBytes_cons b i hb]
      simp only [cmpL]
      rw [ih (i + 1) (by omega)]
    · rw [dif_neg hb, drop_toBytes_nil b i hb]; rfl

/-- `cmpBytes` is the spec order: `.lt` when `a < b`, `.eq` when equal, `.gt` otherwise. -/
theorem cmpBytes_spec (a b : ByteArray) :
    cmpBytes a b = if bytesLt (toBytes a) (toBytes b) then .lt
      else if a = b then .eq else .gt := by
  rw [cmpBytes, cmpFrom_eq, List.drop_zero, List.drop_zero, cmpL_spec]
  by_cases h : bytesLt (toBytes a) (toBytes b) <;> simp only [h, ↓reduceIte]
  by_cases e : a = b
  · subst e; simp
  · have : toBytes a ≠ toBytes b := fun h' => e (toBytes_inj h')
    simp [this, e]

theorem ltBytes_spec (a b : ByteArray) : ltBytes a b = bytesLt (toBytes a) (toBytes b) := by
  unfold ltBytes; rw [cmpBytes_spec]
  cases h : bytesLt (toBytes a) (toBytes b)
  · simp only [Bool.false_eq_true, ↓reduceIte]; split <;> rfl
  · rfl

end LeanKV.Proofs
