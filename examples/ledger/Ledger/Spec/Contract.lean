import Ledger.Spec.Model
import LeanKVSol.Base.Contract

/-!
# Ledger spec: the implementation contract

One hole, `Impl.pick`: how the implementation turns a Ledger command into one LeanKV command,
reading the in-memory index. Its obligation: on every well-formed index it agrees with `pickRef`.
Durability and crash consistency (R15–R17) then come from LeanKV's `substrate_crash_consistent`.
-/

namespace Ledger.Spec
open LeanKV.Spec

/-- English: IMPLEMENTATION HOLE. Turn a Ledger command into one LeanKV command, reading the
in-memory index. -/
def Impl.pick : Tree → LCmd ByteArray → Cmd ByteArray := sorry

/-- English: The obligation: on every well-formed index, the implementation's LeanKV command is
the reference translation `pickRef` (read as spec bytes). -/
theorem impl_pick_ok (t : Tree) (c : LCmd ByteArray) (hw : Store.WellFormed t.toList) :
    (Impl.pick t c).map toBytes = pickRef t.toList (c.map toBytes) := sorry

end Ledger.Spec
