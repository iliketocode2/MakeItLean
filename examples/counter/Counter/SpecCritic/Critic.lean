import Counter.Spec

/-!
# Counter spec critic (Stage 2)

The critic tries to break the spec: it writes wrong implementations and wrong models, and checks
that the spec tells each one apart from the right one. A planted bug the spec accepts is a gap in
the spec, to be fixed before the freeze. Not locked: the critic may add cases at any time.

1. **Wrong translations.** Each must disagree with the model on some concrete store and command,
   so `pickRef_refines` (and through it the obligation `impl_pick_ok`) rejects it.
2. **Wrong models.** Each must give a different answer from the spec on a worked example, so the
   requirement examples actually pin the model down.
-/

namespace Counter.SpecCritic
open LeanKV.Spec Counter.Spec

/-! ## 1. Wrong translations -/

/-- Writes two more instead of one more. -/
def pickTwice (st : Store) : CCmd Bytes → Cmd Bytes
  | .incr n => .put n (u64le (dec st n + 2))
  | c => pickRef st c

/-- Forgets the name-length limit. -/
def pickNoLimit (st : Store) : CCmd Bytes → Cmd Bytes
  | .incr n => if dec st n < maxCount then .put n (u64le (dec st n + 1)) else .get n
  | c => pickRef st c

/-- Does translation `p` change the store as the model changes the state, for command `c` on
store `st` (checked on a few names, including the invalid ones)? -/
def agrees (p : Store → CCmd Bytes → Cmd Bytes) (st : Store) (c : CCmd Bytes) : Bool :=
  let after := dec (step st (p st c)).1
  let want := (cstep (dec st) c).1
  [nm "a", nm "b", [], List.replicate 65 0x61].all fun k => after k == want k

-- the honest translation agrees (the check itself is not vacuous)
#guard agrees pickRef [] (.incr (nm "a"))
#guard agrees pickRef [] (.incr (List.replicate 65 0x61))
-- each planted bug is caught
#guard !agrees pickTwice [] (.incr (nm "a"))
#guard !agrees pickNoLimit [] (.incr (List.replicate 65 0x61))

/-! ## 2. Wrong models -/

/-- Forgets the maximum: increments past 2⁶⁴ − 1. -/
def cstepNoMax (s : CState) : CCmd Bytes → CState × CResp
  | .incr n => if validName n then (s.set n (s n + 1), .value (s n + 1)) else (s, .error)
  | c => cstep s c

/-- Answers the old value instead of the new one. -/
def cstepOldValue (s : CState) : CCmd Bytes → CState × CResp
  | .incr n => if validName n && s n < maxCount then (s.set n (s n + 1), .value (s n)) else (s, .error)
  | c => cstep s c

#guard (cstepNoMax (fun _ => maxCount) (.incr (nm "a"))).2 != (cstep (fun _ => maxCount) (.incr (nm "a"))).2
#guard (cstepOldValue CState.empty (.incr (nm "a"))).2 != (cstep CState.empty (.incr (nm "a"))).2

end Counter.SpecCritic
