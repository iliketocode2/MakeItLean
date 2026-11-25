import AppName.Spec

/-!
# AppName spec critic (Stage 2)

> TEMPLATE: replace these with planted bugs for your own function. `mil audit` requires at least
> one `#guard` here, and checks that every file in `SpecCritic/` elaborates (a failing `#guard`
> fails it).

Wrong implementations the postcondition must reject on at least one input. A planted bug the
postcondition accepts is a gap in the spec, to be fixed before the freeze. Not locked.
-/

namespace AppName.SpecCritic
open AppName.Spec

/-- Always the first input. -/
def wrongFirst (a _b : Int) : Int := a
/-- The smaller input. -/
def wrongMin (a b : Int) : Int := if a ≤ b then a else b
/-- One more than the right answer. -/
def wrongPlusOne (a b : Int) : Int := (if a ≤ b then b else a) + 1

-- the right answer is accepted (the check itself is not vacuous)
#guard decide (maxOf_postcond 3 5 5 trivial)
-- each planted bug is rejected on some input
#guard !decide (maxOf_postcond 3 5 (wrongFirst 3 5) trivial)
#guard !decide (maxOf_postcond 3 5 (wrongMin 3 5) trivial)
#guard !decide (maxOf_postcond 3 5 (wrongPlusOne 3 5) trivial)

end AppName.SpecCritic
