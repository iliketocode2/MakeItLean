import AppName.Spec.Model

/-!
# AppName spec: the implementation contract

One hole, the function itself; its obligation is the postcondition on every allowed input.
-/

namespace AppName.Spec

/-- English: IMPLEMENTATION HOLE. The function, on inputs that meet the precondition. -/
def Impl.maxOf (a : Int) (b : Int) (h : maxOf_precond a b) : Int := sorry

/-- English: The obligation: on every allowed input, the implementation's result meets the
postcondition. -/
theorem impl_maxOf_ok (a : Int) (b : Int) (h : maxOf_precond a b) :
    maxOf_postcond a b (Impl.maxOf a b h) h := sorry

end AppName.Spec
