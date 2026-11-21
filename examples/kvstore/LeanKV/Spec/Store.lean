import LeanKV.Spec.Contract
import LeanKV.Spec.Wire
import LeanKV.Spec.Log

/-!
# LeanKV spec: the durable store against a model file system (R10, R11, R12, R21)

The store is written once, generic over its file operations (`LogFile m`).
- For the proofs it runs on `FsM`, a model file system with crashes and injected I/O faults.
- In production it runs on real files, where it is tested by the R23 harness.

The theorems say:
- an acknowledged write survives any crash;
- after any crash, recovery yields exactly the acknowledged writes, plus possibly the one
  that was in flight;
- the store blocks itself after an I/O error;
- the store refuses a corrupt log without touching it.

**What the model covers (proven).** The model file system tracks two versions of the log:
`content`, which reads see, and `durable`, the content as of the last successful `sync`. A
crash leaves a prefix of either version, at least as long as their common prefix. So:
- unsynced appends may be lost, kept, or partly kept;
- an unsynced truncation may or may not have happened.

An I/O error may leave part of an append behind.

**What the model leaves out (tested by R23, not proven).** After a crash, unsynced regions
may hold *garbage*: bytes that are not a prefix of anything written, such as pages persisted
out of order. Random bytes could, with a chance of about 2⁻⁶⁴, form a valid record, so no
proof can cover them.

**Not modelled.** The file and directory are assumed to exist (the shell creates them; this
is tested). There are no concurrent writers (non-goal).
-/

namespace LeanKV.Spec

/-! ## File operations -/

/-- English: The file operations the store may use, over any monad `m`: read the whole log,
append bytes, make everything appended so far durable (fsync), and truncate to a length.
`none` or `false` means an I/O error. -/
class LogFile (m : Type → Type) where
  /-- English: Read the whole log. -/
  readAll : m (Option ByteArray)
  /-- English: Append bytes to the end of the log. -/
  append : ByteArray → m Bool
  /-- English: Make everything written so far durable (fsync). -/
  sync : m Bool
  /-- English: Cut the log down to the given length. -/
  truncate : Nat → m Bool

/-! ## The model file system -/

/-- English: The model disk. `content` is what reads see; `durable` is the content as of the
last successful sync, which is all that is guaranteed to survive a crash. -/
structure Disk where
  /-- English: What reads see now. -/
  content : Bytes
  /-- English: The content as of the last successful sync. -/
  durable : Bytes
  deriving Repr, DecidableEq

/-- English: Whether a file operation succeeds or fails. When an append fails, the first
`keep` bytes of it may still have reached the file. -/
inductive Fault where
  /-- English: The operation succeeds. -/
  | ok
  /-- English: The operation fails with an I/O error; a failed append leaves its first `keep`
  bytes behind. -/
  | fail (keep : Nat)
  deriving Repr, DecidableEq

/-- English: The model file system's state: the disk, and the scripted outcome of each
upcoming file operation, used in order. Once the script runs out, every operation succeeds. -/
structure FsState where
  /-- English: The model disk. -/
  disk : Disk
  /-- English: The outcomes of the upcoming file operations, in order. -/
  faults : List Fault
  deriving Repr

/-- English: The monad of the model file system. -/
abbrev FsM := StateM FsState

/-- English: Take the outcome of the next file operation from the script. -/
def popFault : FsM Fault :=
  modifyGet fun s => match s.faults with
    | [] => (.ok, s)
    | f :: fs => (f, { s with faults := fs })

/-- English: The model file system's file operations. Read returns `content`. Append extends
`content`, and a failed append may extend it with a prefix of the bytes. Sync sets `durable` to
`content`, and a failed sync changes nothing. Truncate shortens `content`. -/
instance : LogFile FsM where
  readAll := do
    match ← popFault with
    | .ok => return some (ofBytes (← get).disk.content)
    | .fail _ => return none
  append bs := do
    match ← popFault with
    | .ok =>
      modify fun s => { s with disk := { s.disk with content := s.disk.content ++ toBytes bs } }
      return true
    | .fail k =>
      modify fun s =>
        { s with disk := { s.disk with content := s.disk.content ++ (toBytes bs).take k } }
      return false
  sync := do
    match ← popFault with
    | .ok =>
      modify fun s => { s with disk := { s.disk with durable := s.disk.content } }
      return true
    | .fail _ => return false
  truncate n := do
    match ← popFault with
    | .ok =>
      modify fun s => { s with disk := { s.disk with content := s.disk.content.take n } }
      return true
    | .fail _ => return false

/-- English: The length of the longest common prefix of two byte strings. -/
def commonPrefixLen : Bytes → Bytes → Nat
  | a :: as, b :: bs => if a == b then commonPrefixLen as bs + 1 else 0
  | _, _ => 0

/-- English: How a crash is resolved: whether the old durable version or the current version
survives, and how much of it survives. -/
structure CrashChoice where
  /-- English: True if the old durable version survives, false if the current version does. -/
  keepDurable : Bool
  /-- English: How many bytes of that version survive. -/
  len : Nat
  deriving Repr

/-- English: The log left on disk after a crash (R11). It is a prefix of the durable or the
current version, never shorter than the prefix the two have in common. Every `CrashChoice`
gives an allowed outcome, and every allowed outcome comes from some `CrashChoice`. After the
crash, the file's content is durable. -/
def crashOutcome (d : Disk) (ch : CrashChoice) : Bytes :=
  let base := if ch.keepDurable then d.durable else d.content
  base.take (max (commonPrefixLen d.durable d.content) ch.len)

/-- English: The store state a log stands for: the reference store after replaying its
recovered batches, or nothing if the log is corrupt. -/
def logState (b : Bytes) : Option Store := (recover b).state?

/-! ## The store: implementation holes -/

/-- English: An open store: its in-memory index, whether it has hit an I/O error (after which
it refuses everything until reopened, R11), and a spare number for the implementation's own use
(for example, the log length). -/
structure Handle where
  /-- English: The in-memory index. -/
  index : Tree
  /-- English: Whether the store has hit an I/O error. -/
  failed : Bool
  /-- English: A spare number for the implementation's own bookkeeping. -/
  aux : Nat

/-- English: IMPLEMENTATION HOLE. Open the store: read and recover the log, truncate a torn
tail durably (R12), and build the index. Return either an open store or an error reply
(`ERR CORRUPT` or `ERR IO`). Written once for every monad with file operations. -/
def Impl.openStore {m : Type → Type} [Monad m] [LogFile m] :
    m (Except (Reply ByteArray) Handle) := sorry

/-- English: IMPLEMENTATION HOLE. Run one command on an open store and return the updated store
and the reply. A write must be durable before it is acknowledged (R10). Written once for every
monad with file operations. -/
def Impl.exec {m : Type → Type} [Monad m] [LogFile m] (h : Handle) (c : Cmd ByteArray) :
    m (Handle × Reply ByteArray) := sorry

/-! ## Sessions and `check`, parameterized by the implementation

Spec definitions never call a hole themselves; they take the implementation's functions as
parameters, and only the theorems below name the holes. (A definition that called a hole would
compile differently once the hole is filled, and the comparator would reject it.)
-/

/-- English: Run commands one after another on an open store with exec function `ex`, returning
the final store and every reply in order. -/
def execAllWith {m : Type → Type} [Monad m]
    (ex : Handle → Cmd ByteArray → m (Handle × Reply ByteArray)) (h : Handle) :
    List (Cmd ByteArray) → m (Handle × List (Reply ByteArray))
  | [] => pure (h, [])
  | c :: cs => do
    let (h', r) ← ex h c
    let (h'', rs) ← execAllWith ex h' cs
    pure (h'', r :: rs)

/-- English: One session: open the store with `op`, then run the commands with `ex`. -/
def sessionWith {m : Type → Type} [Monad m] (op : m (Except (Reply ByteArray) Handle))
    (ex : Handle → Cmd ByteArray → m (Handle × Reply ByteArray)) (cmds : List (Cmd ByteArray)) :
    m (Except (Reply ByteArray) (Handle × List (Reply ByteArray))) := do
  match ← op with
  | .error r => pure (.error r)
  | .ok h => .ok <$> execAllWith ex h cmds

/-- English: The `check` command (R21), using recovery function `rec`: read the log and report
the recovery outcome. It only reads, so it cannot modify the log. -/
def checkWith {m : Type → Type} [Monad m] [LogFile m] (rec : ByteArray → Recovery ByteArray) :
    m (Reply ByteArray) := do
  match ← LogFile.readAll with
  | none => pure (.ioError ByteArray.empty)
  | some b =>
    pure (match rec b with
      | .ok bs n t => .log bs.length n t
      | .corrupt p => .corrupt p)

/-- English: Whether a reply is an I/O error. -/
def Reply.isIOError {β : Type} : Reply β → Bool
  | .ioError _ => true
  | _ => false

/-- English: Whether a reply gives the same answer as a reference response. A limit error's
explanatory detail is not compared. -/
def Reply.matches (r : Reply Bytes) (x : Response Bytes) : Bool :=
  match x, r with
  | .limitError, .limitError _ => true
  | .limitError, _ => false
  | x, r => r == Reply.ofResponse [] x

/-- English: Whether a list of implementation replies answers, one for one, exactly like a list
of reference responses: same length, and each reply matches its response. -/
def repliesMatch : List (Reply ByteArray) → List (Response Bytes) → Bool
  | [], [] => true
  | r :: rs, x :: xs => (r.map toBytes).matches x && repliesMatch rs xs
  | _, _ => false

/-- English: The model file system at the start of a session: the log `c0` is on disk and
durable, and file operations follow the fault script `φ`. -/
def startState (c0 : Bytes) (φ : List Fault) : FsState := ⟨⟨c0, c0⟩, φ⟩

/-! ## Required properties (proven in Stage 4) -/

/-- English: Without I/O faults, a session on a healthy log answers every command exactly as
the reference model does, starting from the state the log stands for (R4–R10). The index then
holds exactly the reference store, and its height is within the R17 bound. -/
theorem store_no_faults {c0 : Bytes} {s0 : Store} (hs0 : logState c0 = some s0)
    (cmds : List (Cmd ByteArray)) :
    ∃ h rs, ((sessionWith (m := FsM) Impl.openStore Impl.exec cmds).run (startState c0 [])).1 = .ok (h, rs) ∧
      repliesMatch rs (runFrom s0 (cmds.map (Cmd.map toBytes))).2 = true ∧
      h.index.toList = (runFrom s0 (cmds.map (Cmd.map toBytes))).1 ∧
      h.index.height ≤ 3 * Nat.log2 (h.index.size + 1) + 2 := sorry

/-- English: Crash consistency (R10, R11). Run a session on a healthy log with any I/O faults,
then crash in any allowed way.
- **If open fails,** it reports an I/O error and the log still stands for the same state.
- **Otherwise,** the replies match the reference up to some command j. From j on, every reply
  is an I/O error, so the store blocks itself after a failure. After the crash, the log stands
  for the reference state after the first j commands (every acknowledged write survives), or
  after the first j+1 (the write in flight was applied in full). -/
theorem store_crash_consistent {c0 : Bytes} {s0 : Store} (hs0 : logState c0 = some s0)
    (cmds : List (Cmd ByteArray)) (φ : List Fault) (ch : CrashChoice) :
    let scmds := cmds.map (Cmd.map toBytes)
    let out := (sessionWith (m := FsM) Impl.openStore Impl.exec cmds).run (startState c0 φ)
    let c1 := crashOutcome out.2.disk ch
    match out.1 with
    | .error r => r.isIOError = true ∧ logState c1 = some s0
    | .ok (_, rs) => ∃ j ≤ cmds.length,
        rs.length = cmds.length ∧
        repliesMatch (rs.take j) ((runFrom s0 scmds).2.take j) = true ∧
        (∀ r ∈ rs.drop j, r.isIOError = true) ∧
        (logState c1 = some (runFrom s0 (scmds.take j)).1 ∨
          (j < cmds.length ∧ logState c1 = some (runFrom s0 (scmds.take (j + 1))).1)) := sorry

/-- English: Refusing a corrupt log (R12). If the log is corrupt at offset p, the session fails
with `ERR CORRUPT p` (or with an I/O error, if reading fails), and the log is left exactly as it
was. -/
theorem store_refuses_corrupt {c0 : Bytes} {p : Nat} (hc : recover c0 = .corrupt p)
    (cmds : List (Cmd ByteArray)) (φ : List Fault) :
    let out := (sessionWith (m := FsM) Impl.openStore Impl.exec cmds).run (startState c0 φ)
    (out.1 = .error (.corrupt p) ∨ ∃ d, out.1 = .error (.ioError d)) ∧
      out.2.disk = ⟨c0, c0⟩ := sorry

/-- English: `check` never modifies the log (R21), and it reports the reference recovery
outcome. -/
theorem storeCheck_spec (st : FsState) :
    ((checkWith (m := FsM) Impl.recover).run st).2.disk = st.disk ∧
      (((checkWith (m := FsM) Impl.recover).run st).1.isIOError = true ∨
        ((checkWith (m := FsM) Impl.recover).run st).1.map toBytes =
          match recover st.disk.content with
          | .ok bs n t => .log bs.length n t
          | .corrupt p => .corrupt p) := sorry

end LeanKV.Spec
