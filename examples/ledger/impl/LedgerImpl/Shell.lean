import LedgerImpl.Core
import LeanKVImpl.Shell.FileIO

/-!
# `ledger`: the Ledger CLI (trusted shell, REQUIREMENTS.md R14)

    ledger <dir> open NAME
    ledger <dir> deposit NAME AMOUNT
    ledger <dir> withdraw NAME AMOUNT
    ledger <dir> transfer FROM TO AMOUNT
    ledger <dir> balance NAME
    ledger <dir> accounts
    ledger <dir> total

The store is LeanKV's proven core on real files (`<dir>/leankv.log`). Each command goes through
`execPick` with the proven `LedgerImpl.pick`, so Ledger inherits LeanKV's durability and crash
consistency (`substrate_crash_consistent`). The printed answer is the spec's `cstep` evaluated on
the ledger the index stood for before the command. This file (argument parsing, answer
formatting, exit codes) is trusted, not verified: keep it thin.
-/

open LeanKV.Spec LeanKV.Shell Ledger.Spec

/-- Bytes of an ASCII name as text (valid names are ASCII, R2). -/
def nameText (n : Bytes) : String := String.ofList (n.map fun b => Char.ofNat b.toNat)

/-- An amount argument: one or more decimal digits (R4, D3); anything else is a usage error. -/
def parseAmount (s : String) : Option Nat :=
  if !s.isEmpty && s.toList.all Char.isDigit then s.toNat? else none

/-- The error code text of §3. -/
def errText : LErr → String
  | .badName => "BAD_NAME"
  | .badAmount => "BAD_AMOUNT"
  | .accountExists => "ACCOUNT_EXISTS"
  | .unknownAccount n => s!"UNKNOWN_ACCOUNT {nameText n}"
  | .insufficientFunds => "INSUFFICIENT_FUNDS"
  | .balanceLimit => "BALANCE_LIMIT"
  | .sameAccount => "SAME_ACCOUNT"

/-- The answer line (R14) and its exit code. -/
def render : LResp → String × UInt32
  | .ok => ("OK", 0)
  | .balance b => (s!"BALANCE {b}", 0)
  | .accounts l =>
    (" ".intercalate (s!"ACCOUNTS {l.length}" :: l.map fun p => s!"{nameText p.1} {p.2}"), 0)
  | .total t => (s!"TOTAL {t}", 0)
  | .err e => (s!"ERR {errText e}", 1)

def usageText : String :=
  "ERR USAGE usage: ledger <dir> open NAME | deposit NAME AMOUNT | withdraw NAME AMOUNT | " ++
  "transfer FROM TO AMOUNT | balance NAME | accounts | total"

/-- Parse the command words after `<dir>`. -/
def parseCmd : List String → Option (LCmd ByteArray)
  | ["open", n] => some (.openAccount n.toUTF8)
  | ["deposit", n, a] => (parseAmount a).map (.deposit n.toUTF8)
  | ["withdraw", n, a] => (parseAmount a).map (.withdraw n.toUTF8)
  | ["transfer", f, t, a] => (parseAmount a).map (.transfer f.toUTF8 t.toUTF8)
  | ["balance", n] => some (.balance n.toUTF8)
  | ["accounts"] => some .accounts
  | ["total"] => some .total
  | _ => none

def run (args : List String) : IO UInt32 := do
  match args with
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
        let (line, code) := render (cstep (dec h.index.toList) (c.map toBytes)).2
        IO.println line
        return code
      | _ => IO.println "ERR IO no reply"; return 4
  | [] => IO.println usageText; return 2

def main (args : List String) : IO UInt32 := run args
