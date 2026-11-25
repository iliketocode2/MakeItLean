import AppName.Spec

/-!
# AppName spec critic (Stage 2)

> TEMPLATE: replace these with planted bugs for your own library. `mil audit` requires at least one
> `#guard` here, and checks that every file in `SpecCritic/` elaborates (a failing `#guard` fails it).

Wrong implementations the contract must reject: each differs from the reference on some input the
obligation covers, so no proof of `Impl.f = f` can exist for it. And one check that the obligation's
precondition matters: the early-stopping `member` is wrong on a list that is not ascending, which is
why `impl_member_ok` assumes `Ascending`. Not locked: the critic may add cases at any time.
-/

namespace AppName.SpecCritic
open AppName.Spec

/-- Appends instead of inserting in order. -/
def insertAppend (x : Nat) (s : NatSet) : NatSet := if member x s then s else s ++ [x]
/-- Inserts even when the element is already there. -/
def insertDup (x : Nat) : NatSet → NatSet
  | [] => [x]
  | y :: ys => if x ≤ y then x :: y :: ys else y :: insertDup x ys
/-- Looks only at the first element. -/
def memberHead (x : Nat) : NatSet → Bool
  | [] => false
  | y :: _ => x == y
/-- Stops early, like the implementation, but without the ascending order to rely on. -/
def memberEarly (x : Nat) : NatSet → Bool
  | [] => false
  | y :: ys => if x < y then false else if x = y then true else memberEarly x ys

-- each planted bug differs from the reference on an input the obligation covers
#guard insertAppend 1 [2, 3] != insertSorted 1 [2, 3]
#guard insertDup 2 [1, 2] != insertSorted 2 [1, 2]
#guard memberHead 2 [1, 2] != member 2 [1, 2] && decide (Ascending [1, 2])
-- the precondition matters: on a list that is not ascending, stopping early is wrong
#guard memberEarly 1 [3, 1] != member 1 [3, 1] && !decide (Ascending [3, 1])
-- the checks are not vacuous: the reference agrees with itself on the same inputs
#guard insertSorted 1 [2, 3] == [1, 2, 3]

end AppName.SpecCritic
