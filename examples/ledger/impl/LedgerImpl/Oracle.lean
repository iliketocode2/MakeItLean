import LedgerImpl.Text

/-!
# `ledger-oracle`: the reference model as a process (test oracle, REQUIREMENTS.md R19)

Reads protocol lines on stdin and answers each with the **frozen spec's** `cstep`, run from the
empty ledger: no store, no files, no implementation code. A differential test feeds the same
lines to the real system (`ledger <dir> serve`, or the HTTP API through `http/adapter.ts`) and to
this oracle and requires identical answers (`tools/difftest.py`). The model is the frozen spec;
only the line parsing and printing (`LedgerImpl.Text`, shared with the shell) are code here.
-/

open LeanKV.Spec Ledger.Spec LedgerImpl

partial def loop (stdin stdout : IO.FS.Stream) (s : LState) : IO Unit := do
  let line ← stdin.getLine
  if line.isEmpty then return
  match parseCmd (words line) with
  | none => stdout.putStrLn "ERR USAGE"; stdout.flush; loop stdin stdout s
  | some c =>
    let (s', r) := cstep s (c.map toBytes)
    stdout.putStrLn (render r).1; stdout.flush
    loop stdin stdout s'

def main : IO Unit := do loop (← IO.getStdin) (← IO.getStdout) []
