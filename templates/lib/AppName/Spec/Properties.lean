import AppName.Spec.Model

/-!
# AppName spec: properties of the reference, and worked examples

Theorems that relate the functions (what a user of the library relies on), and every worked example
from the requirements as an executable check (`#guard`, run at build time). Proven at Stage 2,
before the freeze.
-/

namespace AppName.Spec

/-- English: An element is in the result of inserting `x` exactly when it is `x` or was already in
the set. -/
theorem mem_insertSorted (x z : Nat) (s : NatSet) : z ∈ insertSorted x s ↔ z = x ∨ z ∈ s := by
  induction s with
  | nil => simp [insertSorted]
  | cons y ys ih =>
    simp only [insertSorted]
    split
    · simp
    · split
      · rename_i h; subst h; simp
      · simp only [List.mem_cons, ih]
        constructor
        · rintro (h | h | h) <;> simp [h]
        · rintro (h | h | h) <;> simp [h]

/-- English: Inserting into a valid (ascending) set gives a valid set. -/
theorem ascending_insertSorted (x : Nat) (s : NatSet) (h : Ascending s) : Ascending (insertSorted x s) := by
  induction s with
  | nil => simp [insertSorted]
  | cons y ys ih =>
    simp only [Ascending, List.pairwise_cons] at h ⊢
    simp only [insertSorted]
    split
    · rename_i hxy
      simp only [List.pairwise_cons, List.mem_cons]
      refine ⟨?_, h.1, h.2⟩
      intro z hz
      rcases hz with rfl | hz
      · exact hxy
      · exact Nat.lt_trans hxy (h.1 z hz)
    · split
      · simp only [List.pairwise_cons]; exact h
      · rename_i hxy hne
        simp only [List.pairwise_cons]
        refine ⟨?_, ih h.2⟩
        intro z hz
        rcases (mem_insertSorted x z ys).1 hz with rfl | hz
        · omega
        · exact h.1 z hz

/-- English: After inserting `x`, the set contains `x`. -/
theorem member_insertSorted (x : Nat) (s : NatSet) : member x (insertSorted x s) = true := by
  induction s with
  | nil => simp [insertSorted, member]
  | cons y ys ih =>
    simp only [insertSorted]
    split
    · simp [member]
    · split
      · rename_i h; subst h; simp [member]
      · simp [member, ih]

/-- English: Inserting adds at most one element. -/
theorem size_insertSorted_le (x : Nat) (s : NatSet) : size (insertSorted x s) ≤ size s + 1 := by
  induction s with
  | nil => simp [insertSorted, size]
  | cons y ys ih =>
    simp only [insertSorted, size] at ih ⊢
    split
    · simp
    · split
      · simp
      · simp; omega

/-! ## Worked examples (REQUIREMENTS.md), checked at build time -/

-- inserting 3, 1, 2 into the empty set gives [1, 2, 3]; inserting 2 again changes nothing
#guard insertSorted 2 (insertSorted 1 (insertSorted 3 [])) == [1, 2, 3]
#guard insertSorted 2 [1, 2, 3] == [1, 2, 3]
-- membership and size
#guard member 2 [1, 2, 3] && !member 4 [1, 2, 3]
#guard size [1, 2, 3] == 3
-- validity: ascending lists are sets, others are not
#guard decide (Ascending [1, 2, 3]) && !decide (Ascending [2, 1]) && !decide (Ascending [1, 1])

end AppName.Spec
