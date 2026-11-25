/-! Bait leaves, outside the verified modules: what verified code may and may not depend on. -/
namespace BaitLeaf
/-- The code the program would really run for `succLeaf`. -/
def fastSucc (n : Nat) : Nat := n + 2
/-- Bad: the kernel checks `n + 1`, the program runs `fastSucc`. -/
@[implemented_by fastSucc] def succLeaf (n : Nat) : Nat := n + 1
/-- Bad: the kernel checks the body, the program runs the C function. -/
@[extern "bait_c_succ"] def externSucc (n : Nat) : Nat := n + 1
/-- Fine: an opaque leaf; no proof can depend on its behaviour. -/
@[extern "bait_c_ok"] opaque okLeaf : Nat → Nat
end BaitLeaf
