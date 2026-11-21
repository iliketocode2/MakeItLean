import LeanKVSol.Base.Store

/-!
# LeanKV shell: the real-file `LogFile` instance (Stage 5)

TRUSTED, NOT PROVEN. The `@[extern]` functions are the C leaf in `c/lkv_io.c`. This instance
is the real-file counterpart of the model file system `FsM` that the store is proven against.
It is checked by the real-file differential tests and the kill tests (TRUST.md).
-/

namespace LeanKV.Shell
open LeanKV.Spec

/-- Open (or create) the log, lock it exclusively, return its file descriptor. -/
@[extern "lkv_open"] opaque lkvOpen (path : @& String) : IO UInt32
/-- Read the whole log. -/
@[extern "lkv_read_all"] opaque lkvReadAll (fd : UInt32) : IO ByteArray
/-- Append bytes to the log. -/
@[extern "lkv_append"] opaque lkvAppend (fd : UInt32) (b : @& ByteArray) : IO Unit
/-- fsync the log. -/
@[extern "lkv_fsync"] opaque lkvFsync (fd : UInt32) : IO Unit
/-- Truncate the log to a length. -/
@[extern "lkv_truncate"] opaque lkvTruncate (fd : UInt32) (n : @& Nat) : IO Unit
/-- Close the log. -/
@[extern "lkv_close"] opaque lkvClose (fd : UInt32) : IO Unit

/-- The real-file monad: IO with the log's file descriptor. -/
abbrev RealM := ReaderT UInt32 IO

/-- Real files: any I/O error becomes `none`/`false`, exactly as the model's faults do. -/
instance : LogFile RealM where
  readAll := fun fd => do try return some (← lkvReadAll fd) catch _ => return none
  append b := fun fd => do try lkvAppend fd b; return true catch _ => return false
  sync := fun fd => do try lkvFsync fd; return true catch _ => return false
  truncate n := fun fd => do try lkvTruncate fd n; return true catch _ => return false

end LeanKV.Shell
