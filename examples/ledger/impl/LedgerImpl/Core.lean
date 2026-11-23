import Ledger.Spec.Model
import LeanKVImpl.Core

/-!
# Ledger implementation: turn a command into one LeanKV command, reading the index

The decision logic is the spec's own `pickWith` (the rules of §3, run once per command). What the
implementation adds is the fast balance lookup: `look` reads LeanKV's in-memory balanced tree with
`LeanKV.Core.lookup` (O(log n)) instead of searching the reference list `t.toList` (O(n)).
-/

namespace LedgerImpl
open LeanKV.Spec Ledger.Spec

/-- The balance stored under account `n` in the index, or `none` if there is no such account. -/
def look (t : Tree) (n : Bytes) : Option Nat :=
  (LeanKV.Core.lookup t (ofBytes n)).map (fun v => decodeBal (toBytes v))

/-- Intended filling of `Impl.pick`: decide with the spec's rules on fast lookups, then turn the
chosen LeanKV command into byte arrays. -/
def pick (t : Tree) (c : LCmd ByteArray) : Cmd ByteArray :=
  (pickWith (look t) (c.map toBytes)).map ofBytes

end LedgerImpl
