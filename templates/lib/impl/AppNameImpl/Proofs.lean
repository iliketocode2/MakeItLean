import AppNameImpl.Core

/-! Proofs of the AppName obligations: each implementation function equals its reference. -/

namespace AppNameImpl
open AppName.Spec

theorem insertSorted_ok (x : Nat) (s : NatSet) : insertSorted x s = AppName.Spec.insertSorted x s := rfl

theorem size_ok (s : NatSet) : size s = AppName.Spec.size s := rfl

/-- In an ascending set, an element smaller than the first is in none of it. -/
theorem member_below (x y : Nat) (ys : NatSet) (h : Ascending (y :: ys)) (hx : x < y) :
    AppName.Spec.member x (y :: ys) = false := by
  induction ys generalizing y with
  | nil => simp [AppName.Spec.member]; omega
  | cons z zs ih =>
    simp only [Ascending, List.pairwise_cons, List.mem_cons] at h
    have hyz : y < z := h.1 z (Or.inl rfl)
    have hrest : Ascending (z :: zs) := by
      simp only [Ascending, List.pairwise_cons]; exact h.2
    have := ih z hrest (Nat.lt_trans hx hyz)
    simp only [AppName.Spec.member] at this ⊢
    simp [this]; omega

/-- The early-stopping `member` equals the reference on every ascending set. -/
theorem member_ok (x : Nat) (s : NatSet) (h : Ascending s) : member x s = AppName.Spec.member x s := by
  induction s with
  | nil => rfl
  | cons y ys ih =>
    have hys : Ascending ys := (List.pairwise_cons.1 h).2
    simp only [member]
    split
    · rename_i hxy; exact (member_below x y ys h hxy).symm
    · split
      · rename_i hxy; subst hxy; simp [AppName.Spec.member]
      · rename_i h1 h2
        rw [ih hys]; simp [AppName.Spec.member]; omega

end AppNameImpl
