import AppNameImpl.Core

/-! Proof of the AppName obligation. -/

namespace AppNameImpl
open AppName.Spec

theorem maxOf_ok (a : Int) (b : Int) (h : maxOf_precond a b) :
    maxOf_postcond a b (maxOf a b h) h := by
  simp only [maxOf_postcond, maxOf]
  split <;> omega

end AppNameImpl
