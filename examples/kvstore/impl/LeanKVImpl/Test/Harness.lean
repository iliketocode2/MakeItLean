import LeanKVImpl.Core.Store
import LeanKVImpl.Proofs.FsOps

/-!
# R23: the deterministic fault and corruption harness (Stage 5)

Drives the store over the simulated file system (`FsM`) with seeded faults, *including what the
proofs leave out*:
- garbage crashes: the unsynced region is replaced by random bytes;
- bit flips anywhere in the durable log.

Sessions are chained, with a crash between each. The expected outcome always comes from the
Lean spec (`step`, `recover`, the record boundaries). The mutation gate runs four store variants
with planted bugs, each of which must be caught.

Run: `lake env lean LeanKVImpl/Test/Harness.lean`. Every failure prints its seed.
-/

open LeanKV.Spec LeanKV.Proofs

/-- A store implementation under test. -/
structure Impl where
  name : String
  openS : FsM (Except (Reply ByteArray) Handle)
  execS : Handle → Cmd ByteArray → FsM (Handle × Reply ByteArray)

/-! ## Mutants -/

inductive Bug | ackBeforeSync | noTruncate | noPoison | openIgnoresCorruption

def mutExec (bug : Bug) (h : Handle) (c : Cmd ByteArray) : FsM (Handle × Reply ByteArray) := do
  if h.failed then return (h, .ioError ByteArray.empty)
  let (t', resp) := LeanKV.Core.step h.index c
  match LeanKV.Core.writesOf c, resp with
  | some ops, .ok =>
    let ok1 ← LogFile.append (LeanKV.Core.encodeRecord ops)
    if !ok1 then
      return ({ h with failed := !(bug matches .noPoison) }, .ioError ByteArray.empty)
    if bug matches .ackBeforeSync then return ({ h with index := t' }, .ok)
    let ok2 ← LogFile.sync
    if !ok2 then
      return ({ h with failed := !(bug matches .noPoison) }, .ioError ByteArray.empty)
    return ({ h with index := t' }, .ok)
  | _, _ => return ({ h with index := t' }, Reply.ofResponse ByteArray.empty resp)

def mutOpen (bug : Bug) : FsM (Except (Reply ByteArray) Handle) := do
  match ← LogFile.readAll with
  | none => return .error (.ioError ByteArray.empty)
  | some b =>
    let r := match LeanKV.Core.recover b, bug with
      | .corrupt _, .openIgnoresCorruption =>
        let (bs, n) := LeanKV.Core.readFrom b (b.size + 1) 0; Recovery.ok bs n (b.size - n)
      | r, _ => r
    match r with
    | .corrupt p => return .error (.corrupt p)
    | .ok bs n t =>
      if t > 0 && !(bug matches .noTruncate) then
        unless ← LogFile.truncate n do return .error (.ioError ByteArray.empty)
        unless ← LogFile.sync do return .error (.ioError ByteArray.empty)
      return .ok ⟨bs.foldl (fun t ops => ops.foldl LeanKV.Core.applyOp t) .leaf, false, n⟩

def core : Impl := ⟨"core (proven)", LeanKV.Core.openStore, LeanKV.Core.exec⟩
def mutant (b : Bug) (name : String) : Impl := ⟨name, mutOpen b, mutExec b⟩

/-! ## Random generation -/

def lcg (x : Nat) : Nat := (x * 1103515245 + 12345) % 2147483648
def key (x : Nat) : ByteArray := ⟨#[(0x61 + x % 12).toUInt8]⟩
def val (x : Nat) : ByteArray := ⟨(List.range (x % 20)).toArray.map fun i => ((x + i) % 256).toUInt8⟩

def genCmds (seed len : Nat) : List (Cmd ByteArray) :=
  (List.range len).map fun i =>
    let x := lcg (seed * 1000 + i)
    match x % 6 with
    | 0 | 1 | 2 => .put (key (x / 7)) (val (x / 11))
    | 3 => .delete (key (x / 7))
    | 4 => .get (key (x / 7))
    | _ => .batch [.put (key (x / 13)) (val x), .delete (key (x / 17))]

def genFaults (seed : Nat) : List Fault :=
  (List.range 12).map fun i =>
    let x := lcg (seed * 77 + i)
    if x % 7 == 0 then .fail (x / 7 % 40) else .ok

def garbage (seed : Nat) : Bytes := (List.range (seed % 50)).map fun i => (lcg (seed + i) % 256).toUInt8

def execAllI (im : Impl) (h : Handle) : List (Cmd ByteArray) → FsM (Handle × List (Reply ByteArray))
  | [] => pure (h, [])
  | c :: cs => do let (h', r) ← im.execS h c; let (h'', rs) ← execAllI im h' cs; pure (h'', r :: rs)

/-! ## The checks -/

/-- Chained sessions with faults and crashes (prefix or garbage). Returns `false` on any
disagreement with the spec. -/
def sessionsOk (im : Impl) (seed : Nat) : Bool := Id.run do
  let mut disk : Bytes := []
  let mut s : Store := Store.empty
  for sess in [0:4] do
    let φ := if sess == 3 then [] else genFaults (seed * 5 + sess)
    let cmds := genCmds (seed * 7 + sess) 10
    let scmds := cmds.map (Cmd.map toBytes)
    let (res, st) := (do
        match ← im.openS with
        | .error r => pure (Sum.inl r)
        | .ok h => Sum.inr <$> execAllI im h cmds : FsM _).run ⟨⟨disk, disk⟩, φ⟩
    -- allowed states after a crash, and the replies
    let mut allowed : List Store := [s]
    match res with
    | .inl r => if !r.isIOError then return false
    | .inr (_, rs) =>
      let j := (rs.findIdx? Reply.isIOError).getD rs.length
      if !repliesMatch (rs.take j) ((runFrom s scmds).2.take j) then return false
      if !(rs.drop j).all Reply.isIOError then return false
      allowed := [(runFrom s (scmds.take j)).1] ++
        (if j < cmds.length then [(runFrom s (scmds.take (j + 1))).1] else [])
    -- crash: keep a prefix of either version, or replace the unsynced region with garbage
    let d := st.disk
    let x := lcg (seed * 13 + sess)
    let L := commonPrefixLen d.durable d.content
    disk := match x % 3 with
      | 0 => crashOutcome d ⟨x % 2 == 0, x / 3 % (d.content.length + 1)⟩
      | 1 => d.durable.take L ++ garbage (x / 5)
      | _ => d.content
    -- the reopened store must stand for one of the allowed states
    match logState disk with
    | none => return false
    | some s' =>
      if !allowed.contains s' then return false
      s := s'
  return true

/-- Record start offsets of a clean log. -/
def recordStarts (b : Bytes) : List Nat :=
  let rec go (fuel off : Nat) (rest : Bytes) : List Nat :=
    match fuel, decodeRecord rest with
    | f + 1, some (_, n) => off :: go f (off + n) (rest.drop n)
    | _, _ => []
  go (b.length + 1) 0 b

/-- Bit flips in a durable, clean log: a flip in any record but the last must be refused as
corrupt at that record's start; a flip in the last record drops it (the accepted limitation). -/
def flipsOk (im : Impl) (seed : Nat) : Bool := Id.run do
  let cmds := genCmds seed 8
  let ((res, st)) := (do
      match ← im.openS with
      | .error r => pure (Sum.inl r)
      | .ok h => Sum.inr <$> execAllI im h cmds : FsM _).run ⟨⟨[], []⟩, []⟩
  if res matches .inl _ then return false
  let log := st.disk.content
  let starts := recordStarts log
  if starts.length < 2 then return true
  let lastStart := starts.getLast!
  for k in [0:6] do
    let i := lcg (seed * 3 + k) % log.length
    let bit := lcg (seed + k) % 8
    let flipped := log.set i (log[i]! ^^^ (1 <<< bit).toUInt8)
    let start := (starts.filter (· ≤ i)).getLast!
    let (r, st') := (im.openS : FsM _).run ⟨⟨flipped, flipped⟩, []⟩
    if i < lastStart then
      -- must refuse, at the start of the damaged record, and leave the file alone
      match r with
      | .error (.corrupt p) => if p != start || st'.disk.content != flipped then return false
      | _ => return false
    else
      -- last record damaged: opens without it
      match r with
      | .ok h => if h.index.toList != (logState (log.take lastStart)).getD [] then return false
      | _ => return false
  return true

def report (im : Impl) : String × Nat × Nat :=
  let seeds := List.range 150
  let fails := seeds.filter fun s => !(sessionsOk im s && flipsOk im s)
  (im.name, seeds.length - fails.length, fails.length)

#eval [report core,
  report (mutant .ackBeforeSync "MUTANT ack before fsync"),
  report (mutant .noTruncate "MUTANT no torn-tail truncate"),
  report (mutant .noPoison "MUTANT keeps going after I/O error"),
  report (mutant .openIgnoresCorruption "MUTANT opens a corrupt log")]

-- Gate: the proven core passes every seed, and every planted bug is caught at least once.
#guard (report core).2.2 == 0
#guard [Bug.ackBeforeSync, .noTruncate, .noPoison, .openIgnoresCorruption].all
  fun b => (report (mutant b "m")).2.2 > 0
