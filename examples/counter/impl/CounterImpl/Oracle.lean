import CounterImpl.Text

/-!
# `counter-oracle`: the reference model as a process (test oracle)

Reads protocol lines on stdin and answers each with the **spec's** `cstep`, run from the empty
state: no store, no files, no implementation. A differential test feeds the same lines to the
real system (`counter <dir> serve`, or an HTTP shell through an adapter) and to this oracle and
requires identical answers (`tools/difftest.py`). The model is the frozen spec; only the line
parsing and printing (`CounterImpl.Text`, shared with the shell) are code here.
-/

open LeanKV.Spec Counter.Spec CounterImpl

partial def loop (stdin stdout : IO.FS.Stream) (s : CState) : IO Unit := do
  let line ← stdin.getLine
  if line.isEmpty then return
  match parseCmd (words line) with
  | none => stdout.putStrLn "ERR USAGE"; stdout.flush; loop stdin stdout s
  | some c =>
    let (s', r) := cstep s (c.map toBytes)
    stdout.putStrLn (render r); stdout.flush
    loop stdin stdout s'

def main : IO Unit := do loop (← IO.getStdin) (← IO.getStdout) (fun _ => 0)
