import LeanKVImpl.Core.Store

/-!
# LeanKV as a substrate for other apps (Phase 2)

An app keeps its state in the LeanKV store. Each app command is turned into exactly one KV
command (a read, or an atomic batch) by `pick`, from the current in-memory index. The app
inherits durability and crash consistency from LeanKV's proven store (`Proofs/Substrate.lean`);
it only proves that `pick` implements its own spec.
-/

namespace LeanKV.Core
open LeanKV.Spec

/-- Run app commands on an open store: each is turned into one KV command by `pick` from the
current index. Written once for every monad with file operations. -/
def execPick {m : Type → Type} [Monad m] [LogFile m] {C : Type} (pick : Tree → C → Cmd ByteArray)
    (h : Handle) : List C → m (Handle × List (Reply ByteArray))
  | [] => pure (h, [])
  | c :: cs => do
    let (h', r) ← exec h (pick h.index c)
    let (h'', rs) ← execPick pick h' cs
    pure (h'', r :: rs)

end LeanKV.Core
