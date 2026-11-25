/-!
# AppName spec: the reference library

A library is specified by **reference implementations**: the simplest correct code for each
function, written to be read, not to be fast. The implementation may use any code it likes, as long
as it is proven equal to the reference on the inputs the contract allows. That is how a faster
implementation is licensed: by a proof, not by a test.

> TEMPLATE: a small set of natural numbers, kept as a strictly ascending list. Replace it with your
> library's types and functions.
-/

namespace AppName.Spec

/-- English: A set of natural numbers, represented as a list. -/
abbrev NatSet := List Nat

/-- English: A list is a valid set when it is strictly ascending: every element is smaller than
every element after it (so there are no repeats). -/
@[reducible] def Ascending (s : NatSet) : Prop := s.Pairwise (· < ·)

/-- English: Add `x` to the set, keeping it ascending. Adding an element that is already there
changes nothing. -/
def insertSorted (x : Nat) : NatSet → NatSet
  | [] => [x]
  | y :: ys => if x < y then x :: y :: ys else if x = y then y :: ys else y :: insertSorted x ys

/-- English: Whether `x` is in the set, by comparing it with every element. -/
def member (x : Nat) : NatSet → Bool
  | [] => false
  | y :: ys => x == y || member x ys

/-- English: The number of elements in the set. -/
def size (s : NatSet) : Nat := s.length

end AppName.Spec
