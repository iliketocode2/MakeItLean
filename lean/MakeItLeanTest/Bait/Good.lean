/-! A well-formed spec: every gate must pass on it. -/
namespace GoodSpec
/-- English: IMPLEMENTATION HOLE. The step. -/
def step : Nat → Nat := sorry
/-- English: Run a step function twice. -/
def twice (f : Nat → Nat) (n : Nat) : Nat := f (f n)
/-- English: The obligation: twice the step adds two. -/
theorem step_ok (n : Nat) : twice step n = n + 2 := sorry
/-- English: A proven spec fact. -/
theorem twice_id (n : Nat) : twice id n = n := rfl
end GoodSpec
