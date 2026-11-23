/-!
# AppName spec: the function's contract

A pure function is specified by a **precondition** (which inputs are allowed) and a
**postcondition** (what a correct result satisfies), in the shape VERINA uses: the postcondition
also receives the proof of the precondition. Keep both decidable (`@[reducible]`, built from
decidable pieces) so the worked examples can be checked with `decide`.
-/

namespace AppName.Spec

/-- English: Every pair of integers is allowed. -/
@[reducible] def maxOf_precond (a : Int) (b : Int) : Prop := True

/-- English: The result is one of the two inputs, and neither input is larger than it. -/
@[reducible] def maxOf_postcond (a : Int) (b : Int) (result : Int) (_h : maxOf_precond a b) : Prop :=
  (result = a ∨ result = b) ∧ a ≤ result ∧ b ≤ result

end AppName.Spec
