import LeanKVImpl.Core.Store
/-! Differential test of the core store against the `Spec/Store.lean` theorem conditions on the
model file system (Stage 3). Run: `lake env lean LeanKVImpl/Test/StoreDiff.lean` -/
open LeanKV.Spec

def coreExecAll (h : Handle) : List (Cmd ByteArray) → FsM (Handle × List (Reply ByteArray))
  | [] => pure (h, [])
  | c :: cs => do let (h', r) ← LeanKV.Core.exec h c; let (h'', rs) ← coreExecAll h' cs; pure (h'', r :: rs)

def coreSession (cmds : List (Cmd ByteArray)) : FsM (Except (Reply ByteArray) (Handle × List (Reply ByteArray))) := do
  match ← (LeanKV.Core.openStore : FsM _) with
  | .error r => pure (.error r)
  | .ok h => .ok <$> coreExecAll h cmds

/-- `store_crash_consistent`, for every allowed crash outcome. -/
def crashOk (c0 : Bytes) (s0 : Store) (cmds : List (Cmd ByteArray)) (φ : List Fault) : Bool :=
  let scmds := cmds.map (Cmd.map toBytes)
  let out := (coreSession cmds).run (startState c0 φ)
  let d := out.2.disk
  let chs := [true, false].flatMap fun kd =>
    (List.range ((if kd then d.durable else d.content).length + 1)).map (CrashChoice.mk kd)
  chs.all fun ch =>
    let c1 := crashOutcome d ch
    match out.1 with
    | .error r => r.isIOError && logState c1 == some s0
    | .ok (_, rs) => (List.range (cmds.length + 1)).any fun j =>
        rs.length == cmds.length && repliesMatch (rs.take j) ((runFrom s0 scmds).2.take j) &&
        (rs.drop j).all Reply.isIOError &&
        (logState c1 == some (runFrom s0 (scmds.take j)).1 ||
          (j < cmds.length && logState c1 == some (runFrom s0 (scmds.take (j + 1))).1))

/-- `store_no_faults`. -/
def noFaultsOk (c0 : Bytes) (s0 : Store) (cmds : List (Cmd ByteArray)) : Bool :=
  let scmds := cmds.map (Cmd.map toBytes)
  match ((coreSession cmds).run (startState c0 [])).1 with
  | .ok (h, rs) => repliesMatch rs (runFrom s0 scmds).2 && h.index.toList == (runFrom s0 scmds).1 &&
      decide (h.index.height ≤ 3 * Nat.log2 (h.index.size + 1) + 2)
  | .error _ => false

/-- `store_refuses_corrupt`. -/
def corruptOk (c0 : Bytes) (p : Nat) (cmds : List (Cmd ByteArray)) (φ : List Fault) : Bool :=
  let out := (coreSession cmds).run (startState c0 φ)
  let r := match out.1 with
    | .error (.corrupt q) => q == p
    | .error (.ioError _) => true
    | _ => false
  r && out.2.disk == ⟨c0, c0⟩

def a (s : String) : ByteArray := s.toUTF8
def cmds : List (Cmd ByteArray) := [.put (a "a") (a "1"), .get (a "a"), .batch [.put (a "b") (a "2"), .delete (a "a")],
  .put ByteArray.empty (a "x"), .scan ByteArray.empty .unbounded 10, .delete (a "b")]
def faultKinds : List Fault := [.ok, .fail 0, .fail 5]
def scripts : Nat → List (List Fault)
  | 0 => [[]]
  | n + 1 => [] :: (faultKinds.flatMap fun f => (scripts n).map (f :: ·))
def rec0 := encodeRecord [.put (toBytes (a "z")) (toBytes (a "9"))]
def torn := rec0 ++ (encodeRecord [.put (toBytes (a "y")) (toBytes (a "8"))]).take 7
def corrupt := rec0 ++ toBytes (a "junk") ++ rec0

def results :=
  let starts : List Bytes := [[], torn]
  let crash := starts.flatMap fun c0 => (scripts 5).map fun φ => crashOk c0 ((logState c0).getD []) cmds φ
  let nf := starts.all fun c0 => noFaultsOk c0 ((logState c0).getD []) cmds
  let cor := (scripts 3).all fun φ => corruptOk corrupt rec0.length cmds φ
  -- multi-session: crash at the end of each session, reopen, continue (no faults)
  let multi := Id.run do
    let mut disk : Bytes := []
    let mut s : Store := []
    let mut ok := true
    for i in [0:5] do
      let out := (coreSession cmds).run (startState disk [])
      disk := crashOutcome out.2.disk ⟨i % 2 == 0, 0⟩
      s := (runFrom s (cmds.map (Cmd.map toBytes))).1
      ok := ok && logState disk == some s
    return ok
  (crash.filter id |>.length, crash.filter (! ·) |>.length, nf, cor, multi)

#eval results
-- Gate: all crash scenarios pass and every other check holds.
#guard results.2.1 == 0 && results.2.2.1 && results.2.2.2.1 && results.2.2.2.2
