import MakeItLeanTest.Bait.Good
/-! Bait shells for the shell gate: one calls the verified function through a helper, one bypasses it. -/
namespace BaitWiring
/-- The verified function (stands for a filled hole). -/
def verifiedStep (n : Nat) : Nat := n + 1
/-- A shell helper that calls it. -/
def helper (n : Nat) : Nat := verifiedStep n
/-- An honest shell entry point (reaches `verifiedStep` through `helper`). -/
def honestMain (n : Nat) : Nat := helper n * 2
/-- A shell that reimplements the step instead of calling the verified one. -/
def bypassMain (n : Nat) : Nat := n + 1
end BaitWiring
