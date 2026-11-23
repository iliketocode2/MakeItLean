import Ledger.Spec.Model

/-!
# Ledger's line protocol (trusted, shared; REQUIREMENTS.md R14, R18, R19)

One command per line (`open NAME`, `deposit NAME AMOUNT`, …), one answer per line (`OK`,
`BALANCE b`, `ACCOUNTS …`, `TOTAL t`, `ERR <CODE> [detail]`). The one-shot CLI, `ledger <dir>
serve` and `ledger-oracle` all parse and print with these functions, so a differential test of
serve (or of the HTTP API through its adapter) against the oracle compares like with like.

This file is trusted, not verified. A bug here would be the same on both sides of a differential
test; `tests/cli_test.sh` and the literal HTTP examples, written from the requirements, cover it.
-/

namespace LedgerImpl
open LeanKV.Spec Ledger.Spec

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

/-- The answer line (R14) and the CLI's exit code for it. -/
def render : LResp → String × UInt32
  | .ok => ("OK", 0)
  | .balance b => (s!"BALANCE {b}", 0)
  | .accounts l =>
    (" ".intercalate (s!"ACCOUNTS {l.length}" :: l.map fun p => s!"{nameText p.1} {p.2}"), 0)
  | .total t => (s!"TOTAL {t}", 0)
  | .err e => (s!"ERR {errText e}", 1)

/-- The CLI's usage message (exit 2). Serve mode and the oracle answer plain `ERR USAGE` instead. -/
def usageText : String :=
  "ERR USAGE usage: ledger <dir> open NAME | deposit NAME AMOUNT | withdraw NAME AMOUNT | " ++
  "transfer FROM TO AMOUNT | balance NAME | accounts | total"

/-- Parse the command words (after `<dir>` on the command line, or one protocol line). -/
def parseCmd : List String → Option (LCmd ByteArray)
  | ["open", n] => some (.openAccount n.toUTF8)
  | ["deposit", n, a] => (parseAmount a).map (.deposit n.toUTF8)
  | ["withdraw", n, a] => (parseAmount a).map (.withdraw n.toUTF8)
  | ["transfer", f, t, a] => (parseAmount a).map (.transfer f.toUTF8 t.toUTF8)
  | ["balance", n] => some (.balance n.toUTF8)
  | ["accounts"] => some .accounts
  | ["total"] => some .total
  | _ => none

/-- The words of one protocol line: split on spaces, one or more (R18). The line's newline is
dropped (a line read with `getLine` has at most one, at its end), and empty words are ignored. -/
def words (line : String) : List String :=
  let line := String.ofList (line.toList.filter (· != '\n'))
  (line.splitOn " ").filter (fun w => !w.isEmpty)

end LedgerImpl
