import MakeItLeanTest.Bait.Leaf
/-! Bait "verified" code that is clean itself but depends on leaves outside the verified modules. -/
namespace BaitVerifiedLeaf
/-- Proven about the body of an `@[implemented_by]` helper: the program runs other code. -/
def viaHelper (n : Nat) : Nat := BaitLeaf.succLeaf n
theorem viaHelper_eq (n : Nat) : viaHelper n = n + 1 := rfl
/-- Proven about the body of an `@[extern]` definition. -/
def viaExtern (n : Nat) : Nat := BaitLeaf.externSucc n
theorem viaExtern_eq (n : Nat) : viaExtern n = n + 1 := rfl
/-- Fine: uses an opaque leaf. -/
def viaOpaque (n : Nat) : Nat := BaitLeaf.okLeaf n
end BaitVerifiedLeaf
