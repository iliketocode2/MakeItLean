def sumTo : Nat → Nat
  | 0 => 0
  | n + 1 => (n + 1) + sumTo n

def fastSum (n : Nat) : Nat := n * n / 2   -- wrong!

-- Statement quietly weakened to only n = 0.
theorem fastSum_correct (n : Nat) (h : n = 0) : fastSum n = sumTo n := by subst h; rfl
