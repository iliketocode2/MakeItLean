import Ledger.Spec

/-!
Spec critic for the Ledger spec (Stage 2). Run with
`lake env lean Ledger/SpecCritic/Critic.lean` in `examples/ledger/`.

1. **Wrong translations.** Planted-bug versions of `pickRef` (what a wrong `Impl.pick` would
   compute) are run through LeanKV's `step` on stores reached by real Ledger runs. The honest
   `pickRef` must refine `cstep` on every case; each bug must break refinement on at least one,
   and so is also rejected by `impl_pick_ok` (which demands equality with `pickRef`).
2. **Wrong models.** Planted-bug versions of `cstep` are checked against the *statements* of the
   R11–R13 theorems on concrete good ledgers. Each bug must violate at least one statement, which
   shows the theorems have teeth (they are not vacuous).
-/

open LeanKV.Spec Ledger.Spec

/-! ## 1. Wrong translations -/

inductive TBug | honest | debitOnly | overdraft | noLimit | reopen | bigEndian | selfTransfer
  deriving DecidableEq, Repr

def beBytes (v : Nat) : Bytes := (u64le v).reverse

def pickBug (bug : TBug) (st : Store) (c : LCmd Bytes) : Cmd Bytes :=
  match bug, c with
  | .debitOnly, .transfer f t a =>
    match plan (balOf st) (.transfer f t a) with
    | .write ((n, v) :: _) _ => .put n (u64le v)
    | _ => readNothing
  | .overdraft, .transfer f t a =>
    match balOf st f, balOf st t with
    | some bf, some bt =>
      if validName f && validName t && f != t && validAmount a then
        .batch [.put f (u64le (bf - a)), .put t (u64le (bt + a))]
      else readNothing
    | _, _ => readNothing
  | .noLimit, .deposit n a =>
    match balOf st n with
    | some b => if validName n && validAmount a then .put n (u64le (b + a)) else readNothing
    | none => readNothing
  | .reopen, .openAccount n => if validName n then .put n (u64le 0) else readNothing
  | .bigEndian, c =>
    match plan (balOf st) c with
    | .write ups _ => .batch (ups.map fun p => .put p.1 (beBytes p.2))
    | _ => readNothing
  | .selfTransfer, .transfer f t a =>
    if f = t then
      match balOf st f with
      | some bf => if a ≤ bf then .batch [.put f (u64le (bf - a)), .put t (u64le (bf + a))]
                   else readNothing
      | none => readNothing
    else pickRef st (.transfer f t a)
  | _, c => pickRef st c

/-- Does the translation refine the model on store `st` and command `c`? -/
def refinesOn (bug : TBug) (st : Store) (c : LCmd Bytes) : Bool :=
  dec (step st (pickBug bug st c)).1 == (cstep (dec st) c).1

def setupScripts : List (List (LCmd Bytes)) :=
  [[], [.openAccount (nm "a")],
   [.openAccount (nm "a"), .openAccount (nm "b"), .deposit (nm "a") 100],
   [.openAccount (nm "a"), .openAccount (nm "b"), .deposit (nm "a") 100,
    .deposit (nm "b") (maxBalance - 5)]]

def probeCmds : List (LCmd Bytes) :=
  [.openAccount (nm "a"), .openAccount (nm "c"), .deposit (nm "a") 7, .deposit (nm "b") 10,
   .withdraw (nm "a") 30, .withdraw (nm "a") 300, .transfer (nm "a") (nm "b") 40,
   .transfer (nm "a") (nm "b") 400, .transfer (nm "a") (nm "a") 5, .transfer (nm "b") (nm "a") 1,
   .balance (nm "a"), .accounts, .total]

def stores : List Store := setupScripts.map (kvRun [])

def caught (bug : TBug) : Bool :=
  stores.any fun st => probeCmds.any fun c => !refinesOn bug st c

-- The honest translation refines the model on every case …
#guard stores.all fun st => probeCmds.all fun c => refinesOn .honest st c
-- … and every planted bug is caught.
#guard caught .debitOnly
#guard caught .overdraft
#guard caught .noLimit
#guard caught .reopen
#guard caught .bigEndian
#guard caught .selfTransfer

/-! ## 2. Wrong models against the R11–R13 statements -/

inductive MBug | honest | creditPlusOne | overdraftWithdraw | refuseButWrite | touchOther
  deriving DecidableEq, Repr

def cstepBug (bug : MBug) (s : LState) (c : LCmd Bytes) : LState × LResp :=
  match bug, c with
  | .creditPlusOne, .transfer _ t _ =>
    match (cstep s c) with
    | (s', .ok) => (s'.set t ((s'.bal t).getD 0 + 1), .ok)
    | r => r
  | .overdraftWithdraw, .withdraw n a =>
    match s.bal n with
    | some b => if validName n && validAmount a then (s.set n (b - a), .balance (b - a))
                else cstep s c
    | none => cstep s c
  | .refuseButWrite, .deposit n _ =>
    match cstep s c with
    | (_, .err e) => (s.set n 0, .err e)
    | r => r
  | .touchOther, .openAccount _ =>
    match cstep s c with
    | (s', .ok) => (s'.set (nm "zz") 0, .ok)
    | r => r
  | _, c => cstep s c

def goodStates : List LState := setupScripts.map fun cs => (lrun [] cs).1

/-- R11 (refused changes nothing), R11 (only named accounts change), R13 (one-step total). -/
def statementsHold (bug : MBug) (s : LState) (c : LCmd Bytes) : Bool :=
  let (s', r) := cstepBug bug s c
  let r11a := match r with | .err _ => s' == s | _ => true
  let r11b := [nm "a", nm "b", nm "c", nm "zz"].all fun m => c.names.contains m || s'.bal m == s.bal m
  let r13 := s'.total + flowOut c r == s.total + flowIn c r
  r11a && r11b && r13

def mCaught (bug : MBug) : Bool :=
  goodStates.any fun s => probeCmds.any fun c => !statementsHold bug s c

-- The honest model satisfies the statements on every case …
#guard goodStates.all fun s => probeCmds.all fun c => statementsHold .honest s c
-- … and every planted model bug violates one of them.
#guard mCaught .creditPlusOne
#guard mCaught .overdraftWithdraw
#guard mCaught .refuseButWrite
#guard mCaught .touchOther

/-! ## 3. Non-vacuity of the run-level theorems on the example script -/
#guard (lrun [] exampleScript).1.total + outflow exampleScript (lrun [] exampleScript).2 ==
  inflow exampleScript (lrun [] exampleScript).2
#guard inflow exampleScript (lrun [] exampleScript).2 == 1000
#guard outflow exampleScript (lrun [] exampleScript).2 == 300
