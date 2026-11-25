import AppName.Spec.Model

/-!
# AppName spec: the implementation contract

One hole per function, and one obligation per hole: the implementation equals the reference. An
obligation may assume what the spec guarantees about its inputs: `member` may rely on the set being
ascending (so it can stop early), and `Properties.lean` proves that `insertSorted` keeps it so.
-/

namespace AppName.Spec

/-- English: IMPLEMENTATION HOLE. `insertSorted`, as the implementation computes it. -/
def Impl.insertSorted (x : Nat) (s : NatSet) : NatSet := sorry

/-- English: IMPLEMENTATION HOLE. `member`, as the implementation computes it. -/
def Impl.member (x : Nat) (s : NatSet) : Bool := sorry

/-- English: IMPLEMENTATION HOLE. `size`, as the implementation computes it. -/
def Impl.size (s : NatSet) : Nat := sorry

/-- English: The obligation for `insertSorted`: the implementation gives exactly the reference's
result, for every element and every list. -/
theorem impl_insertSorted_ok (x : Nat) (s : NatSet) : Impl.insertSorted x s = insertSorted x s := sorry

/-- English: The obligation for `member`: on every ascending set, the implementation gives exactly
the reference's answer. -/
theorem impl_member_ok (x : Nat) (s : NatSet) (h : Ascending s) : Impl.member x s = member x s := sorry

/-- English: The obligation for `size`: the implementation gives exactly the reference's count. -/
theorem impl_size_ok (s : NatSet) : Impl.size s = size s := sorry

end AppName.Spec
