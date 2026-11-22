import CounterImpl.Core
import LeanKVImpl.Shell.FileIO

/-!
# `counter`: the Counter CLI (trusted shell)

    counter <dir> incr <name>     add one; print the new value
    counter <dir> get <name>      print the value

The store is LeanKV's proven core on real files; each command goes through `execPick`, so the
Counter inherits LeanKV's durability and crash consistency (`substrate_crash_consistent`).
-/

open LeanKV.Spec LeanKV.Shell Counter.Spec

def answer (before : Tree) (c : CCmd ByteArray) (r : Reply ByteArray) : String :=
  if r.isIOError then "ERR IO"
  else match (cstep (dec before.toList) (c.map toBytes)).2 with
    | .value v => s!"VALUE {v}"
    | .error => "ERR"

def main (args : List String) : IO UInt32 := do
  match args with
  | [dir, verb, name] =>
    let c : CCmd ByteArray ← match verb with
      | "incr" => pure (.incr name.toUTF8)
      | "get" => pure (.get name.toUTF8)
      | _ => IO.println "usage: counter <dir> incr|get <name>"; return 2
    IO.FS.createDirAll dir
    let fd ← lkvOpen (dir ++ "/leankv.log")
    match ← (LeanKV.Core.openStore : RealM _).run fd with
    | .error _ => IO.println "ERR IO"; return 4
    | .ok h =>
      let (_, rs) ← (LeanKV.Core.execPick CounterImpl.pick h [c] : RealM _).run fd
      let line := answer h.index c (rs.headD (.ioError ByteArray.empty))
      IO.println line
      return if line.startsWith "VALUE" then 0 else 1
  | _ => IO.println "usage: counter <dir> incr|get <name>"; return 2
