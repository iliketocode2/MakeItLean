import AppName.Spec.Model

/-! AppName implementation. Each function fills one hole; `Proofs.lean` proves it equal to the
spec's reference. -/

namespace AppNameImpl
open AppName.Spec

/-- Intended filling of `Impl.insertSorted`: the reference itself (no faster version needed). -/
def insertSorted (x : Nat) (s : NatSet) : NatSet := AppName.Spec.insertSorted x s

/-- Intended filling of `Impl.member`: stops at the first element larger than `x`. Faster than the
reference on a miss, and correct only because the set is ascending: the proof uses that. -/
def member (x : Nat) : NatSet → Bool
  | [] => false
  | y :: ys => if x < y then false else if x = y then true else member x ys

/-- Intended filling of `Impl.size`. -/
def size (s : NatSet) : Nat := s.length

end AppNameImpl
