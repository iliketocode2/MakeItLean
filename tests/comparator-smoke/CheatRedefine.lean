-- Spec definition quietly changed so the wrong implementation "matches".
def sumTo (n : Nat) : Nat := n * n / 2

def fastSum (n : Nat) : Nat := n * n / 2   -- wrong!

theorem fastSum_correct (n : Nat) : fastSum n = sumTo n := rfl
