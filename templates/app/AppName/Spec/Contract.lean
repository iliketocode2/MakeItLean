import AppName.Spec.Model
import LeanKVSol.Base.Contract

/-!
# AppName spec: the implementation contract

One hole, `Impl.pick`: how the implementation turns a command into one LeanKV command, reading
the in-memory index. Its obligation: on every well-formed index it agrees with `pickRef`.
Durability and crash consistency then come from LeanKV's substrate theorem.
-/

namespace AppName.Spec
open LeanKV.Spec

/-- English: IMPLEMENTATION HOLE. Turn a command into one LeanKV command, reading the index. -/
def Impl.pick : Tree → CCmd ByteArray → Cmd ByteArray := sorry

/-- English: The obligation: on every well-formed index, the implementation's translation is the
reference translation `pickRef` (read as spec bytes). -/
theorem impl_pick_ok (t : Tree) (c : CCmd ByteArray) (hw : Store.WellFormed t.toList) :
    (Impl.pick t c).map toBytes = pickRef t.toList (c.map toBytes) := sorry

end AppName.Spec
