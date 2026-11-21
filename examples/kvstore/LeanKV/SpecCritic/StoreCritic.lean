import LeanKV.Spec.Store
open LeanKV.Spec

/-! A reference store plus mutants, checked against `store_crash_consistent` by exhaustive enumeration. -/

structure H where
  s : Store
  failed : Bool

inductive Bug | none | ackBeforeSync | noTruncate | noPoison deriving DecidableEq

def isWrite : Cmd Bytes → Option (List (WriteOp Bytes))
  | .put k v => some [.put k v] | .delete k => some [.delete k] | .batch ops => some ops | _ => none

def refOpen [Monad m] [LogFile m] (bug : Bug) : m (Except (Reply ByteArray) H) := do
  match ← LogFile.readAll with
  | none => return .error (.ioError ByteArray.empty)
  | some b =>
    match recover (toBytes b) with
    | .corrupt p => return .error (.corrupt p)
    | r@(.ok _ n t) =>
      if t > 0 && bug != .noTruncate then
        unless ← LogFile.truncate n do return .error (.ioError ByteArray.empty)
        unless ← LogFile.sync do return .error (.ioError ByteArray.empty)
      return .ok ⟨r.state?.getD [], false⟩

def refExec [Monad m] [LogFile m] (bug : Bug) (h : H) (c : Cmd ByteArray) : m (H × Reply ByteArray) := do
  if h.failed then return (h, .ioError ByteArray.empty)
  let c' := c.map toBytes
  let (s', resp) := step h.s c'
  let reply : Reply ByteArray := (Reply.ofResponse [] resp).map ofBytes
  match isWrite c', resp with
  | some ops, .ok =>
    let ok1 ← LogFile.append (ofBytes (encodeRecord ops))
    if !ok1 then return ({ h with failed := bug != .noPoison }, .ioError ByteArray.empty)
    if bug == .ackBeforeSync then return ({ h with s := s' }, reply)
    let ok2 ← LogFile.sync
    if !ok2 then return ({ h with failed := bug != .noPoison }, .ioError ByteArray.empty)
    return ({ h with s := s' }, reply)
  | _, _ => return (h, reply)

def refExecAll [Monad m] [LogFile m] (bug : Bug) (h : H) : List (Cmd ByteArray) → m (H × List (Reply ByteArray))
  | [] => pure (h, [])
  | c :: cs => do let (h', r) ← refExec bug h c; let (h'', rs) ← refExecAll bug h' cs; pure (h'', r :: rs)

def refSession (bug : Bug) (cmds : List (Cmd ByteArray)) : FsM (Except (Reply ByteArray) (H × List (Reply ByteArray))) := do
  match ← refOpen bug with
  | .error r => pure (.error r)
  | .ok h => .ok <$> refExecAll bug h cmds

/-- The `store_crash_consistent` condition, evaluated for every allowed crash outcome. -/
def holds (bug : Bug) (c0 : Bytes) (s0 : Store) (cmds : List (Cmd ByteArray)) (φ : List Fault) : Bool :=
  let scmds := cmds.map (Cmd.map toBytes)
  let out := (refSession bug cmds).run (startState c0 φ)
  let d := out.2.disk
  let chs := [true, false].flatMap (fun kd => (List.range ((if kd then d.durable else d.content).length + 1)).map (fun n => CrashChoice.mk kd n))
  chs.all fun ch =>
    let c1 := crashOutcome d ch
    match out.1 with
    | .error r => r.isIOError && logState c1 == some s0
    | .ok (_, rs) => (List.range (cmds.length + 1)).any fun j =>
        rs.length == cmds.length &&
        repliesMatch (rs.take j) ((runFrom s0 scmds).2.take j) &&
        (rs.drop j).all Reply.isIOError &&
        (logState c1 == some (runFrom s0 (scmds.take j)).1 ||
          (j < cmds.length && logState c1 == some (runFrom s0 (scmds.take (j + 1))).1))

def a (s : String) : ByteArray := s.toUTF8
def cmds : List (Cmd ByteArray) := [.put (a "a") (a "1"), .get (a "a"), .batch [.put (a "b") (a "2"), .delete (a "a")], .put ByteArray.empty (a "x"), .scan ByteArray.empty .unbounded 10]
def faultKinds : List Fault := [.ok, .fail 0, .fail 5]
def scripts : Nat → List (List Fault)
  | 0 => [[]]
  | n + 1 => [] :: (faultKinds.flatMap fun f => (scripts n).map (f :: ·))
-- initial logs: empty, and one record followed by a torn tail
def rec0 := encodeRecord [.put (toBytes (a "z")) (toBytes (a "9"))]
def torn := rec0 ++ (encodeRecord [.put (toBytes (a "y")) (toBytes (a "8"))]).take 7
def starts : List Bytes := [[], torn]

def report (bug : Bug) : Nat × Nat := Id.run do
  let mut pass := 0; let mut fail := 0
  for c0 in starts do
    let s0 := (logState c0).getD []
    for φ in scripts 5 do
      if holds bug c0 s0 cmds φ then pass := pass + 1 else fail := fail + 1
  return (pass, fail)

#eval (logState torn).isSome
#eval [("reference", report .none), ("ack before sync", report .ackBeforeSync), ("no truncate", report .noTruncate), ("no poison", report .noPoison)]
