import CounterImpl.Core
import LeanKVImpl.Proofs

/-! Proof of the Counter obligation. -/

namespace CounterImpl
open LeanKV.Spec Counter.Spec LeanKV.Proofs

theorem countOf_eq {t : Tree} (hw : Store.WellFormed t.toList) (n : ByteArray) :
    countOf t n = dec t.toList (toBytes n) := by
  have e := toList_lookup t n hw.1
  unfold countOf dec
  cases h : LeanKV.Core.lookup t n <;> rw [h] at e <;> simp at e <;> rw [← e]

theorem pick_ok (t : Tree) (c : CCmd ByteArray) (hw : Store.WellFormed t.toList) :
    (pick t c).map toBytes = pickRef t.toList (c.map toBytes) := by
  cases c with
  | get n => rfl
  | incr n =>
    simp only [pick, pickRef, CCmd.map, countOf_eq hw, validName, toBytes_length]
    split <;> simp [Cmd.map, u64leBA, toBytes_ofBytes]

/-- The reference translation, on implementation commands (names as byte arrays). -/
def counterPick (st : Store) (c : CCmd ByteArray) : Cmd Bytes := pickRef st (c.map toBytes)

/-- The model step on implementation commands: `cstep`'s new state. -/
def counterStep (s : CState) (c : CCmd ByteArray) : CState := (cstep s (c.map toBytes)).1

/-- `pick` meets LeanKV's substrate condition. -/
theorem pickOk : PickOk pick counterPick := fun t c hw => pick_ok t c hw

/-- The reference translation refines the Counter model (from the frozen `pickRef_refines`). -/
theorem refines : Refines dec counterStep counterPick := fun _ c hw => pickRef_refines hw _

/-- **Counter crash consistency, end to end.** After any faults and any crash, the recovered log
decodes to the Counter model after exactly the acknowledged commands, possibly plus the one in
flight (`AppOutcome`). -/
theorem crash_consistent {c0 : Bytes} {s0 : Store} (hs0 : logState c0 = some s0)
    (cs : List (CCmd ByteArray)) (φ : List Fault) (ch : CrashChoice) :
    let out := (do
        match ← (LeanKV.Core.openStore : FsM _) with
        | .error r => pure (Except.error r)
        | .ok h => Except.ok <$> LeanKV.Core.execPick pick h cs : FsM _).run (startState c0 φ)
    AppOutcome dec counterStep counterPick s0 cs out.1 (crashOutcome out.2.disk ch) :=
  app_crash_consistent pickOk refines hs0 cs φ ch

end CounterImpl
