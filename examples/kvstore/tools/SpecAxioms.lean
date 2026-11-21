import LeanKV.Spec

/-! Stage 6: in the frozen spec, exactly the 9 implementation obligations may depend on `sorry`
(their proofs live in the implementation and are judged by the comparator); every other spec
theorem must use only `propext`, `Quot.sound`, `Classical.choice`.
Run: `lake env lean tools/SpecAxioms.lean`. -/

open Lean Elab Command

def obligations : List Name :=
  [`LeanKV.Spec.impl_run_eq, `LeanKV.Spec.impl_toList_eq, `LeanKV.Spec.impl_height_le,
   `LeanKV.Spec.impl_encodeRecord_eq, `LeanKV.Spec.impl_recover_eq, `LeanKV.Spec.store_no_faults,
   `LeanKV.Spec.store_crash_consistent, `LeanKV.Spec.store_refuses_corrupt, `LeanKV.Spec.storeCheck_spec]

elab "#check_spec_axioms" : command => do
  let env ← getEnv
  let mut bad := #[]
  let mut withSorry := #[]
  let mut n := 0
  for (nm, ci) in env.constants.toList do
    let some idx := env.getModuleIdxFor? nm | continue
    let some mod := env.header.moduleNames[idx.toNat]? | continue
    unless (`LeanKV.Spec).isPrefixOf mod do continue
    unless ci matches .thmInfo _ do continue
    n := n + 1
    let axs ← liftCoreM (collectAxioms nm)
    if axs.contains ``sorryAx then withSorry := withSorry.push nm
    for a in axs do
      unless a ∈ [``propext, ``Quot.sound, ``Classical.choice, ``sorryAx] do
        bad := bad.push s!"{nm} uses axiom {a}"
  let unexpected := withSorry.filter (· ∉ obligations)
  if !bad.isEmpty || !unexpected.isEmpty || withSorry.size != obligations.length then
    throwError m!"SPEC AXIOMS FAILED: {bad.toList} unexpected sorry: {unexpected.toList}; obligations with sorry: {withSorry.size}"
  logInfo m!"SPEC AXIOMS OK: {n} theorems; only the {obligations.length} implementation obligations are open in the spec"

#check_spec_axioms
