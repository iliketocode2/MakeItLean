import LedgerImpl.Core
import LedgerImpl.Text
import LeanKVImpl.Shell.FileIO

/-!
# `ledger`: the Ledger CLI and serve mode (trusted shell, REQUIREMENTS.md R14, R18)

    ledger <dir> open NAME
    ledger <dir> deposit NAME AMOUNT
    ledger <dir> withdraw NAME AMOUNT
    ledger <dir> transfer FROM TO AMOUNT
    ledger <dir> balance NAME
    ledger <dir> accounts
    ledger <dir> total
    ledger <dir> serve           one command per stdin line, one answer per stdout line (R18)

The store is LeanKV's proven core on real files (`<dir>/leankv.log`). Each command goes through
`execPick` with the proven `LedgerImpl.pick`, so Ledger inherits LeanKV's durability and crash
consistency (`substrate_crash_consistent`). The printed answer is the spec's `cstep` evaluated on
the ledger the index stood for before the command. Parsing and printing are the shared line
protocol (`LedgerImpl.Text`). This file (argument handling, the serve loop, exit codes) is
trusted, not verified: keep it thin.
-/

open LeanKV.Spec LeanKV.Shell Ledger.Spec LedgerImpl

/-- The answer line for command `c` run on the index `before` (the spec's `cstep` on the ledger
the index stands for), and the CLI's exit code for it. -/
def answer (before : Tree) (c : LCmd ByteArray) : String × UInt32 :=
  render (cstep (dec before.toList) (c.map toBytes)).2

/-- Write one answer line and flush it (R18: each answer is flushed as soon as it is written). -/
def emit (out : IO.FS.Stream) (line : String) : IO Unit := do
  out.putStrLn line
  out.flush

/-- Serve: one command per line until end of input (exit 0). A line that is not a command is
answered `ERR USAGE` and serve continues. An I/O error is answered `ERR IO` and is fail-stop
(exit 4): after a failed write the on-disk state is unknown (R16, R18). -/
partial def serveLoop (stdin stdout : IO.FS.Stream) (h : Handle) (fd : UInt32) : IO UInt32 := do
  let line ← stdin.getLine
  if line.isEmpty then return 0
  match parseCmd (words line) with
  | none => emit stdout "ERR USAGE"; serveLoop stdin stdout h fd
  | some c =>
    let res ← try
        let (h', rs) ← (LeanKV.Core.execPick LedgerImpl.pick h [c] : RealM _).run fd
        pure (some (h', rs))
      catch _ => pure none
    match res with
    | some (h', [r]) =>
      if r.isIOError then emit stdout "ERR IO"; return 4
      emit stdout (answer h.index c).1
      serveLoop stdin stdout h' fd
    | _ => emit stdout "ERR IO"; return 4

/-- `ledger <dir> serve` (R18): open the store once, then serve lines. A corrupt store is
`ERR CORRUPT offset p` (exit 3, no file changed, R17); a store that cannot be opened is a line
starting with `ERR IO` (exit 4). Nothing is read from stdin before the store is open. -/
def serve (dir : String) : IO UInt32 := do
  let stdout ← IO.getStdout
  let fd ← try
      IO.FS.createDirAll dir
      lkvOpen (dir ++ "/leankv.log")
    catch e =>
      -- one line: the system's message can contain newlines
      emit stdout ("ERR IO " ++ (toString e).map fun ch => if ch == '\n' then ' ' else ch)
      return 4
  match ← (LeanKV.Core.openStore : RealM _).run fd with
  | .error (.corrupt p) => emit stdout s!"ERR CORRUPT offset {p}"; return 3
  | .error _ => emit stdout "ERR IO open failed"; return 4
  | .ok h => serveLoop (← IO.getStdin) stdout h fd

def run (args : List String) : IO UInt32 := do
  match args with
  | [dir, "serve"] => serve dir
  | dir :: rest =>
    let some c := parseCmd rest | IO.println usageText; return 2
    let fd ← try
        IO.FS.createDirAll dir
        lkvOpen (dir ++ "/leankv.log")
      catch e => IO.println s!"ERR IO {e}"; return 4
    match ← (LeanKV.Core.openStore : RealM _).run fd with
    | .error (.corrupt p) => IO.println s!"ERR CORRUPT offset {p}"; return 3
    | .error _ => IO.println "ERR IO open failed"; return 4
    | .ok h =>
      let (_, rs) ← (LeanKV.Core.execPick LedgerImpl.pick h [c] : RealM _).run fd
      match rs with
      | [r] =>
        if r.isIOError then IO.println "ERR IO write failed"; return 4
        let (line, code) := answer h.index c
        IO.println line
        return code
      | _ => IO.println "ERR IO no reply"; return 4
  | [] => IO.println usageText; return 2

def main (args : List String) : IO UInt32 := run args
