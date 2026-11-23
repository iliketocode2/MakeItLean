import CounterImpl.Core
import CounterImpl.Text
import LeanKVImpl.Shell.FileIO

/-!
# `counter`: the Counter CLI and server (trusted shell)

    counter <dir> incr <name>     add one; print the new value
    counter <dir> get <name>      print the value
    counter <dir> serve           one command per stdin line, one answer per stdout line

The store is LeanKV's proven core on real files; each command goes through `execPick`, so the
Counter inherits LeanKV's durability and crash consistency (`CounterImpl.crash_consistent`).
`serve` keeps the store open (no log replay per command) and stops at the first I/O error.
-/

open LeanKV.Spec LeanKV.Shell Counter.Spec CounterImpl

/-- The answer line for command `c` run on the index `before`, given the store's reply. -/
def answer (before : Tree) (c : CCmd ByteArray) (r : Reply ByteArray) : String :=
  if r.isIOError then "ERR IO" else render (cstep (dec before.toList) (c.map toBytes)).2

/-- Run one command on the open store; the new handle, the answer line, and whether it failed. -/
def runOne (h : Handle) (fd : UInt32) (c : CCmd ByteArray) : IO (Handle × String × Bool) := do
  let (h', rs) ← (LeanKV.Core.execPick CounterImpl.pick h [c] : RealM _).run fd
  let r := rs.headD (.ioError ByteArray.empty)
  return (h', answer h.index c r, r.isIOError)

/-- `serve`: one command per line until end of input; stops at the first I/O error (exit 4). -/
partial def serveLoop (stdin : IO.FS.Stream) (stdout : IO.FS.Stream) (h : Handle) (fd : UInt32) : IO UInt32 := do
  let line ← stdin.getLine
  if line.isEmpty then return 0
  match parseCmd (words line) with
  | none => stdout.putStrLn "ERR USAGE"; stdout.flush; serveLoop stdin stdout h fd
  | some c =>
    let (h', out, failed) ← runOne h fd c
    stdout.putStrLn out; stdout.flush
    if failed then return 4 else serveLoop stdin stdout h' fd

def usage : String := "usage: counter <dir> incr|get <name> | counter <dir> serve"

def main (args : List String) : IO UInt32 := do
  match args with
  | dir :: rest =>
    let serve := rest == ["serve"]
    let c? := parseCmd rest
    if !serve && c?.isNone then IO.println usage; return 2
    IO.FS.createDirAll dir
    let fd ← lkvOpen (dir ++ "/leankv.log")
    match ← (LeanKV.Core.openStore : RealM _).run fd with
    | .error _ => IO.println "ERR IO"; return 4
    | .ok h =>
      if serve then serveLoop (← IO.getStdin) (← IO.getStdout) h fd
      else
        let some c := c? | return 2
        let (_, out, failed) ← runOne h fd c
        IO.println out
        return if failed then 4 else if out.startsWith "VALUE" then 0 else 1
  | _ => IO.println usage; return 2
