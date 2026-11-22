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

end CounterImpl
