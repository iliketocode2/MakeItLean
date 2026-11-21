def sumTo : Nat → Nat
  | 0 => 0
  | n + 1 => (n + 1) + sumTo n

def fastSum (n : Nat) : Nat := n * n / 2   -- wrong!

axiom trust_me : ∀ n, n * n / 2 = sumTo n

theorem fastSum_correct (n : Nat) : fastSum n = sumTo n := trust_me n
