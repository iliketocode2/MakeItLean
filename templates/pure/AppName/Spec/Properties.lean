import AppName.Spec.Model

/-!
# AppName spec: worked examples and checks of the spec itself

Each test from the requirements, as executable checks (`#guard`, run at build time): the
postcondition accepts the expected answer (the spec is **sound** on it) and rejects every wrong
answer listed (the spec is **complete** enough to tell them apart).
-/

namespace AppName.Spec

-- maxOf 3 5 = 5, and 3 is not an acceptable answer
#guard decide (maxOf_postcond 3 5 5 trivial)
#guard !decide (maxOf_postcond 3 5 3 trivial)
-- maxOf (-2) (-7) = -2, and -7 and 0 are not acceptable answers
#guard decide (maxOf_postcond (-2) (-7) (-2) trivial)
#guard !decide (maxOf_postcond (-2) (-7) (-7) trivial)
#guard !decide (maxOf_postcond (-2) (-7) 0 trivial)

/-- English: Equal inputs have exactly one acceptable answer: that value. -/
theorem maxOf_postcond_equal (a r : Int) : maxOf_postcond a a r trivial ↔ r = a := by
  simp only [maxOf_postcond]; omega

end AppName.Spec
