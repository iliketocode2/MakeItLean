import LeanKVImpl.Core.Log
import LeanKVSol.Base.Store

/-!
# LeanKV core: the durable store (Stage 3)

Written once, generic over the spec's `LogFile m`: proven on the model file system (`FsM`)
in Stage 4, run on real files in Stage 5. Intended fillings: `Impl.openStore := openStore`,
`Impl.exec := exec`.

Rules (R10–R12):
- open: read, recover, refuse corruption, truncate a torn tail and sync it before anything else;
- a write is appended and synced before it is acknowledged;
- any I/O error marks the store failed, and it then answers `ERR IO` until reopened.
-/

namespace LeanKV.Core
open LeanKV.Spec

/-- The detail text of an I/O error reply. -/
def ioDetail (what : String) : ByteArray := what.toUTF8

/-- The detail text of a limit error reply. -/
def limitDetail : ByteArray := "size limit exceeded".toUTF8

/-- Open the store. Intended `Impl.openStore`. -/
def openStore {m : Type → Type} [Monad m] [LogFile m] : m (Except (Reply ByteArray) Handle) := do
  match ← LogFile.readAll with
  | none => return .error (.ioError (ioDetail "read failed"))
  | some b =>
    match recover b with
    | .corrupt p => return .error (.corrupt p)
    | .ok bs n t =>
      if t > 0 then
        unless ← LogFile.truncate n do return .error (.ioError (ioDetail "truncate failed"))
        unless ← LogFile.sync do return .error (.ioError (ioDetail "sync failed"))
      let index := bs.foldl (fun t ops => ops.foldl applyOp t) Tree.leaf
      return .ok ⟨index, false, n⟩

/-- The writes a command would log, if it is a write. -/
def writesOf : Cmd ByteArray → Option (List (WriteOp ByteArray))
  | .put k v => some [.put k v]
  | .delete k => some [.delete k]
  | .batch ops => some ops
  | _ => none

/-- Run one command. Intended `Impl.exec`. -/
def exec {m : Type → Type} [Monad m] [LogFile m] (h : Handle) (c : Cmd ByteArray) :
    m (Handle × Reply ByteArray) := do
  if h.failed then return (h, .ioError (ioDetail "store failed; reopen"))
  let (t', resp) := step h.index c
  match writesOf c, resp with
  | some ops, .ok =>
    let rec_ := encodeRecord ops
    unless ← LogFile.append rec_ do
      return ({ h with failed := true }, .ioError (ioDetail "append failed"))
    unless ← LogFile.sync do
      return ({ h with failed := true }, .ioError (ioDetail "sync failed"))
    return ({ index := t', failed := false, aux := h.aux + rec_.size }, .ok)
  | _, _ => return ({ h with index := t' }, Reply.ofResponse limitDetail resp)

end LeanKV.Core
