import AppNameImpl.Proofs
import AppNameSol.Holes
import MakeItLean.Gates

/-! Stage 6: the verified-code audit (run by `mil audit`). The shell is trusted, not verified,
and must not be imported by verified modules. -/
#audit_verified AppNameImpl.Core AppNameImpl.Proofs AppNameSol forbid_imports AppNameImpl.Shell

/-! End-to-end crash consistency: `AppNameImpl.crash_consistent` is `LeanKV.Proofs.app_crash_consistent`
applied to these two facts. Pinning them to the frozen spec's `dec`, `cstep` and `pickRef` means
the theorem is about the approved model and the real `pick`, not a weakened stand-in. -/
open LeanKV.Spec LeanKV.Proofs AppName.Spec in
example : Refines dec (fun (s : CState) (c : CCmd ByteArray) => (cstep s (c.map toBytes)).1) (fun st (c : CCmd ByteArray) => pickRef st (c.map toBytes)) :=
  AppNameImpl.refines
open LeanKV.Spec LeanKV.Proofs AppName.Spec in
example : PickOk AppNameImpl.pick (fun st (c : CCmd ByteArray) => pickRef st (c.map toBytes)) := AppNameImpl.pickOk
