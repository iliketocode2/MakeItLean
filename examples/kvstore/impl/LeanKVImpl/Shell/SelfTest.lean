import LeanKVImpl.Shell.FileIO
import LeanKVImpl.Core.Store
import LeanKVSol.Base.Wire

/-!
# Real-file differential self-test (Stage 5)

The real-file store (core + C leaf) against the spec's reference model. Random command
sequences run in several sessions on real files, closing and reopening between sessions. Every
reply must match the model's answer, and after each session `check` and a full scan must match
the model too. Exit 0 = all agree.
-/

namespace LeanKV.Shell
open LeanKV.Spec

def lcg (x : Nat) : Nat := (x * 1103515245 + 12345) % 2147483648

def key (x : Nat) : ByteArray :=
  if x % 9 == 0 then ⟨#[(0x61 + x % 8).toUInt8, (0xC7 : UInt8), (0x61 + x / 8 % 8).toUInt8]⟩
  else ⟨#[(0x61 + x % 40).toUInt8]⟩

def val (x : Nat) : ByteArray :=
  ⟨(List.range (x % 300)).toArray.map fun i => ((x + i * 7) % 256).toUInt8⟩

def genCmds (seed len : Nat) : List (Cmd ByteArray) := Id.run do
  let mut x := seed
  let mut out := #[]
  for _ in [0:len] do
    x := lcg x
    let k := key (x / 7)
    let c : Cmd ByteArray := match x % 9 with
      | 0 | 1 | 2 | 3 => .put k (val (x / 50))
      | 4 => .delete k
      | 5 => .get k
      | 6 => .scan (if x % 3 == 0 then ByteArray.empty else key (x / 11))
               (if x % 2 == 0 then .unbounded else .below (key (x / 13))) (x / 3 % 12)
      | 7 => .batch [.put k (val (x / 17)), .delete (key (x / 19)), .put (key (x / 23)) ByteArray.empty]
      | _ => if x % 5 == 0 then .put ByteArray.empty k else .delete (key (x / 29))
    out := out.push c
  return out.toList

/-- One seed: several sessions on a fresh real log. Returns an error message on disagreement. -/
def runSeed (dir : String) (seed : Nat) : IO (Option String) := do
  let path := s!"{dir}/selftest-{seed}.log"
  if ← System.FilePath.pathExists path then IO.FS.removeFile path
  let mut model : Store := Store.empty
  for sess in [0:4] do
    let fd ← lkvOpen path
    let cmds := genCmds (seed * 31 + sess) 40
    match ← (Core.openStore : RealM _).run fd with
    | .error r => lkvClose fd; return some s!"seed {seed} session {sess}: open failed {repr (r.map toBytes)}"
    | .ok h0 =>
      let mut h := h0
      for c in cmds do
        let (h', r) ← (Core.exec h c : RealM _).run fd
        let (model', expected) := step model (c.map toBytes)
        unless (r.map toBytes).matches expected do
          lkvClose fd
          return some s!"seed {seed} session {sess}: reply {repr (r.map toBytes)} ≠ model {repr expected}"
        h := h'; model := model'
      lkvClose fd
    -- after the session: what is on disk must recover to the model state
    let fd ← lkvOpen path
    let bytes ← lkvReadAll fd
    let expectedCheck := match recover (toBytes bytes) with
      | .ok bs n t => Reply.log bs.length n t
      | .corrupt p => .corrupt p
    let chk ← (checkWith (m := RealM) Core.recover).run fd
    unless chk.map toBytes == expectedCheck do
      lkvClose fd; return some s!"seed {seed}: check mismatch"
    unless logState (toBytes bytes) == some model do
      lkvClose fd; return some s!"seed {seed} session {sess}: on-disk state ≠ model"
    lkvClose fd
  IO.FS.removeFile path
  return none

def main (args : List String) : IO UInt32 := do
  let dir := args.headD "/tmp"
  let n := (args.drop 1).headD "50" |>.toNat!
  IO.FS.createDirAll dir
  let mut failures := 0
  for seed in [0:n] do
    if let some msg ← runSeed dir seed then
      IO.eprintln msg; failures := failures + 1
  IO.println s!"real-file self-test: {n - failures}/{n} seeds agree with the model ({n * 160} commands, {n * 4} sessions)"
  return if failures == 0 then 0 else 1

end LeanKV.Shell

def main (args : List String) : IO UInt32 := LeanKV.Shell.main args
