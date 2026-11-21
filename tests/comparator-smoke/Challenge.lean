/-! Frozen challenge (the "spec"). Agents may only fill the `sorry`s. -/

/-- English: the reference meaning — the sum 0 + 1 + … + n, computed the slow, obvious way. -/
def sumTo : Nat → Nat
  | 0 => 0
  | n + 1 => (n + 1) + sumTo n

/-- English: an implementation hole — any fast way of computing `sumTo`. -/
def fastSum (n : Nat) : Nat := sorry

/-- English: the fast implementation always agrees with the reference meaning. -/
theorem fastSum_correct (n : Nat) : fastSum n = sumTo n := sorry
