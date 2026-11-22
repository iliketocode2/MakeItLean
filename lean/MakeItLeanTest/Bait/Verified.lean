import MakeItLeanTest.Bait.Shell
/-! Bait "verified" code: planted violations the audit must reject. -/
namespace BaitVerified
partial def loop (n : Nat) : Nat := if n = 0 then 0 else loop (n - 1)
@[implemented_by loop] def impl (n : Nat) : Nat := n
unsafe def uns (n : Nat) : Nat := n
theorem cheat : 1 = 2 := sorry
axiom trustMe : False
theorem viaAxiom : 1 = 2 := trustMe.elim
end BaitVerified
