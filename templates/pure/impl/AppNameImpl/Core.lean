import AppName.Spec.Model

/-! AppName implementation. -/

namespace AppNameImpl
open AppName.Spec

/-- Intended filling of `Impl.maxOf`. -/
def maxOf (a : Int) (b : Int) (_h : maxOf_precond a b) : Int := if a ≤ b then b else a

end AppNameImpl
