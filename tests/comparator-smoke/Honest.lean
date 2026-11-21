def sumTo : Nat → Nat
  | 0 => 0
  | n + 1 => (n + 1) + sumTo n

/-- O(1): Gauss's formula. -/
def fastSum (n : Nat) : Nat := n * (n + 1) / 2

theorem two_mul_sumTo (n : Nat) : 2 * sumTo n = n * (n + 1) := by
  induction n with
  | zero => rfl
  | succ k ih => simp only [sumTo]; rw [Nat.mul_add, ih]; grind

theorem fastSum_correct (n : Nat) : fastSum n = sumTo n := by
  unfold fastSum; rw [← two_mul_sumTo]; omega
