import LeanKVImpl.Proofs.Recover
import LeanKVImpl.Core.Store

/-! The model file system's operations, as plain functions on its state (Stage 4). -/

set_option linter.deprecated false

namespace LeanKV.Proofs
open LeanKV.Spec

/-- The next fault and the remaining script. -/
def nextFault : List Fault → Fault × List Fault
  | [] => (.ok, [])
  | f :: fs => (f, fs)

theorem readAll_run (d : Disk) (fs : List Fault) :
    (LogFile.readAll : FsM _).run ⟨d, fs⟩ =
      (match (nextFault fs).1 with
       | .ok => some (ofBytes d.content)
       | .fail _ => none, ⟨d, (nextFault fs).2⟩) := by
  cases fs with
  | nil => rfl
  | cons f fs => cases f <;> rfl

theorem append_run (d : Disk) (fs : List Fault) (b : ByteArray) :
    (LogFile.append b : FsM _).run ⟨d, fs⟩ =
      match (nextFault fs).1 with
      | .ok => (true, ⟨⟨d.content ++ toBytes b, d.durable⟩, (nextFault fs).2⟩)
      | .fail k => (false, ⟨⟨d.content ++ (toBytes b).take k, d.durable⟩, (nextFault fs).2⟩) := by
  cases fs with
  | nil => rfl
  | cons f fs => cases f <;> rfl

theorem sync_run (d : Disk) (fs : List Fault) :
    (LogFile.sync : FsM _).run ⟨d, fs⟩ =
      match (nextFault fs).1 with
      | .ok => (true, ⟨⟨d.content, d.content⟩, (nextFault fs).2⟩)
      | .fail _ => (false, ⟨d, (nextFault fs).2⟩) := by
  cases fs with
  | nil => rfl
  | cons f fs => cases f <;> rfl

theorem truncate_run (d : Disk) (fs : List Fault) (n : Nat) :
    (LogFile.truncate n : FsM _).run ⟨d, fs⟩ =
      match (nextFault fs).1 with
      | .ok => (true, ⟨⟨d.content.take n, d.durable⟩, (nextFault fs).2⟩)
      | .fail _ => (false, ⟨d, (nextFault fs).2⟩) := by
  cases fs with
  | nil => rfl
  | cons f fs => cases f <;> rfl

theorem bind_run {α β : Type} (x : FsM α) (f : α → FsM β) (st : FsState) :
    (x >>= f).run st = (f (x.run st).1).run (x.run st).2 := rfl

theorem pure_run {α : Type} (a : α) (st : FsState) : (pure a : FsM α).run st = (a, st) := rfl

/-- `check` (core version of `storeCheck_spec`). -/
theorem coreCheck_spec (st : FsState) :
    ((checkWith (m := FsM) Core.recover).run st).2.disk = st.disk ∧
      (((checkWith (m := FsM) Core.recover).run st).1.isIOError = true ∨
        ((checkWith (m := FsM) Core.recover).run st).1.map toBytes =
          match recover st.disk.content with
          | .ok bs n t => .log bs.length n t
          | .corrupt p => .corrupt p) := by
  obtain ⟨d, fs⟩ := st
  unfold checkWith
  rw [bind_run, readAll_run]
  cases hf : (nextFault fs).1 with
  | fail k => exact ⟨rfl, Or.inl rfl⟩
  | ok =>
    refine ⟨rfl, Or.inr ?_⟩
    have e := core_recover_eq (ofBytes d.content)
    rw [toBytes_ofBytes] at e
    simp only [pure_run]
    rw [← e]
    cases Core.recover (ofBytes d.content) <;> simp [Reply.map, Recovery.map]

theorem core_recover_corrupt {c0 : Bytes} {p : Nat} (hc : recover c0 = .corrupt p) :
    Core.recover (ofBytes c0) = .corrupt p := by
  have e := core_recover_eq (ofBytes c0)
  rw [toBytes_ofBytes, hc] at e
  cases h : Core.recover (ofBytes c0) <;> rw [h] at e <;> simp [Recovery.map] at e
  subst e; rfl

/-- Core version of `store_refuses_corrupt`. -/
theorem core_refuses_corrupt {c0 : Bytes} {p : Nat} (hc : recover c0 = .corrupt p)
    (cmds : List (Cmd ByteArray)) (φ : List Fault) :
    let out := (sessionWith (m := FsM) Core.openStore Core.exec cmds).run (startState c0 φ)
    (out.1 = .error (.corrupt p) ∨ ∃ d, out.1 = .error (.ioError d)) ∧
      out.2.disk = ⟨c0, c0⟩ := by
  simp only [startState]
  unfold sessionWith Core.openStore
  rw [bind_run, bind_run, readAll_run]
  cases hf : (nextFault φ).1 with
  | fail k => exact ⟨Or.inr ⟨_, rfl⟩, rfl⟩
  | ok =>
    simp only [core_recover_corrupt hc]
    exact ⟨Or.inl rfl, rfl⟩

end LeanKV.Proofs
