import LeanKVImpl.Shell.FileIO
import LeanKVImpl.Core.Store
import LeanKVSol.Base.Wire

/-!
# `leankv`: the command-line tool and server (R14, R15, R21, R22) — Stage 5

    leankv <dbdir> get|put|delete|scan|batch|check …     one command, exit code per R14
    leankv <dbdir> serve                                  one command per stdin line (R15)

Parsing, printing and exit codes are the spec's proven functions; the store is the proven
core, run on real files through the C leaf.
-/

namespace LeanKV.Shell
open LeanKV.Spec

/-- Write one reply line to stdout. -/
def emit (r : Reply ByteArray) : IO Unit := do
  let out ← IO.getStdout
  out.write (ofBytes (printReply (r.map toBytes) ++ [0x0A]))
  out.flush

/-- Exit code of a reply (R14 table). -/
def code (r : Reply ByteArray) : UInt32 := r.exitCode.toUInt32

/-- A usage-error reply. -/
def usage (msg : String) : Reply ByteArray := .usageError msg.toUTF8

/-- Serve: one command per line until EOF. Usage and limit errors keep going; an I/O error is
fail-stop (exit 4), since after a failed fsync the on-disk state is unknown (R15). -/
partial def serveLoop (stdin : IO.FS.Stream) (h : Handle) (fd : UInt32) : IO UInt32 := do
  let line ← stdin.getLine
  if line.isEmpty then return 0
  let bs := toBytes line.toUTF8
  let bs := if bs.getLast? == some 0x0A then bs.dropLast else bs
  match parseRequest bs with
  | none => emit (usage "bad command"); serveLoop stdin h fd
  | some .check => emit (usage "check is not available while serving"); serveLoop stdin h fd
  | some (.cmd c) =>
    let (h', r) ← (Core.exec h (c.map ofBytes) : RealM _).run fd
    emit r
    if r.isIOError then return 4 else serveLoop stdin h' fd

def run (args : List String) : IO UInt32 := do
  match args with
  | dbdir :: rest@(_ :: _) =>
    IO.FS.createDirAll dbdir
    let fd ← try lkvOpen (dbdir ++ "/leankv.log")
      catch e => do emit (.ioError (toString e).toUTF8); return 4
    if rest == ["serve"] then
      match ← (Core.openStore : RealM _).run fd with
      | .error r => emit r; return code r
      | .ok h => serveLoop (← IO.getStdin) h fd
    else
      match parseRequest (toBytes (" ".intercalate rest).toUTF8) with
      | none => emit (usage "bad command"); return 2
      | some .check =>
        let r ← (checkWith (m := RealM) Core.recover).run fd
        emit r; return code r
      | some (.cmd c) =>
        match ← (Core.openStore : RealM _).run fd with
        | .error r => emit r; return code r
        | .ok h =>
          let (_, r) ← (Core.exec h (c.map ofBytes) : RealM _).run fd
          emit r; return code r
  | _ => emit (usage "usage: leankv <dbdir> <command…> | serve"); return 2

end LeanKV.Shell

def main (args : List String) : IO UInt32 := LeanKV.Shell.run args
