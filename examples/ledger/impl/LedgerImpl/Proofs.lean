import LedgerImpl.Core
import LeanKVImpl.Proofs

/-! Proof of the Ledger obligation `impl_pick_ok`. -/

namespace LedgerImpl
open LeanKV.Spec Ledger.Spec LeanKV.Proofs

/-- Converting a command's bytes to arrays and back gives the same command. -/
theorem cmd_map_toBytes_ofBytes (x : Cmd Bytes) : (x.map ofBytes).map toBytes = x := by
  cases x with
  | get k => simp [Cmd.map, toBytes_ofBytes]
  | put k v => simp [Cmd.map, toBytes_ofBytes]
  | delete k => simp [Cmd.map, toBytes_ofBytes]
  | scan lo hi n => cases hi <;> simp [Cmd.map, Upper.map, toBytes_ofBytes]
  | batch ops =>
    simp only [Cmd.map, List.map_map, Cmd.batch.injEq]
    conv => rhs; rw [← List.map_id ops]
    apply List.map_congr_left
    intro op _
    cases op <;> simp [WriteOp.map, toBytes_ofBytes]

/-- On a well-formed index, the fast lookup is the reference lookup `balOf`. -/
theorem look_eq {t : Tree} (hw : Store.WellFormed t.toList) : look t = balOf t.toList := by
  funext n
  have e := toList_lookup t (ofBytes n) hw.1
  rw [toBytes_ofBytes] at e
  unfold look balOf
  rw [← e, Option.map_map]
  rfl

/-- The obligation: the implementation's LeanKV command is the reference translation. -/
theorem pick_ok (t : Tree) (c : LCmd ByteArray) (hw : Store.WellFormed t.toList) :
    (pick t c).map toBytes = pickRef t.toList (c.map toBytes) := by
  unfold pick pickRef
  rw [cmd_map_toBytes_ofBytes, look_eq hw]

/-! ## Connecting to LeanKV's substrate theorem (R15–R17)

`substrate_crash_consistent pickOk` is the crash-consistency theorem for Ledger: after any crash,
the log stands for `runPick ledgerPick s0 (cs.take j)` (or `j + 1`), where `j` counts the
acknowledged commands. `runPick_eq_kvRun` and the spec's `kvRun_refines` turn that store into the
model ledger `lrun (dec s0) (…)`. -/

/-- The reference translation, on implementation commands (names as byte arrays). -/
def ledgerPick (st : Store) (c : LCmd ByteArray) : Cmd Bytes := pickRef st (c.map toBytes)

/-- Ledger's `pick` meets LeanKV's substrate condition, so `substrate_crash_consistent` and
`substrate_no_faults` apply to Ledger. -/
theorem pickOk : PickOk pick ledgerPick := fun t c hw => pick_ok t c hw

/-- The substrate's reference run of Ledger commands is the spec's `kvRun`. -/
theorem runPick_eq_kvRun (cs : List (LCmd ByteArray)) (s : Store) :
    (runPick ledgerPick s cs).1 = kvRun s (cs.map (LCmd.map toBytes)) := by
  induction cs generalizing s with
  | nil => rfl
  | cons c cs ih => simp only [runPick, List.map_cons, kvRun, ledgerPick]; exact ih _

/-- After any acknowledged prefix of commands from a store standing for ledger `s`, the
substrate's reference store stands for the model ledger after the same commands. -/
theorem runPick_refines (cs : List (LCmd ByteArray)) {s0 : Store} {s : LState} (h : dec s0 = s) :
    dec (runPick ledgerPick s0 cs).1 = (lrun s (cs.map (LCmd.map toBytes))).1 := by
  rw [runPick_eq_kvRun]; exact kvRun_refines _ h

/-- The model step on implementation commands: `cstep`'s new ledger. -/
def ledgerStep (s : LState) (c : LCmd ByteArray) : LState := (cstep s (c.map toBytes)).1

/-- The reference translation refines the Ledger model (from the frozen `pickRef_refines`). -/
theorem refines : Refines dec ledgerStep ledgerPick := fun st c _ => pickRef_refines st _

/-- **Ledger crash consistency (R15–R16), end to end.** Open a store whose log stands for `s0`,
run Ledger commands through the real `pick` under any I/O faults, and crash in any allowed way:
the recovered log decodes to the Ledger model after exactly the acknowledged commands, possibly
plus the one in flight (`AppOutcome`). One kernel-checked theorem; no composition by hand. -/
theorem crash_consistent {c0 : Bytes} {s0 : Store} (hs0 : logState c0 = some s0)
    (cs : List (LCmd ByteArray)) (φ : List Fault) (ch : CrashChoice) :
    let out := (do
        match ← (LeanKV.Core.openStore : FsM _) with
        | .error r => pure (Except.error r)
        | .ok h => Except.ok <$> LeanKV.Core.execPick pick h cs : FsM _).run (startState c0 φ)
    AppOutcome dec ledgerStep ledgerPick s0 cs out.1 (crashOutcome out.2.disk ch) :=
  app_crash_consistent pickOk refines hs0 cs φ ch

end LedgerImpl
