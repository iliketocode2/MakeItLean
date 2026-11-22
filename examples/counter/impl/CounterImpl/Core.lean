import Counter.Spec.Model
import LeanKVImpl.Core

/-! Counter implementation: turn a command into one LeanKV command, reading the index. -/

namespace CounterImpl
open LeanKV.Spec Counter.Spec

/-- A count as 8 bytes, least significant first. -/
def u64leBA (v : Nat) : ByteArray := ofBytes (u64le v)

/-- The count stored under `n` in the index (0 if absent). -/
def countOf (t : Tree) (n : ByteArray) : Nat :=
  match LeanKV.Core.lookup t n with
  | some v => decodeU64 (toBytes v)
  | none => 0

/-- Intended filling of `Impl.pick`. -/
def pick (t : Tree) : CCmd ByteArray → Cmd ByteArray
  | .incr n =>
    if (1 ≤ n.size && n.size ≤ 64) && countOf t n < maxCount then .put n (u64leBA (countOf t n + 1))
    else .get n
  | .get n => .get n

end CounterImpl
