import LeanKVSol.Base.Properties

/-!
# AppName spec: reference model and storage layout

Named appnames. `incr n` adds one and answers the new value; `get n` answers the value (0 if the
appname was never incremented). AppNames live in the LeanKV store: key = the name, value = the
count as 8 bytes, least significant first.
-/

namespace AppName.Spec
open LeanKV.Spec

/-- English: A command, generic in the byte-string type (spec: lists; implementation: arrays). -/
inductive CCmd (β : Type) where
  /-- English: Add one to appname `n` and answer its new value. -/
  | incr (n : β)
  /-- English: Answer the value of appname `n`. -/
  | get (n : β)
  deriving Repr, DecidableEq

/-- English: Change the byte-string representation inside a command. -/
def CCmd.map {β γ : Type} (f : β → γ) : CCmd β → CCmd γ
  | .incr n => .incr (f n)
  | .get n => .get (f n)

/-- English: An answer: a appname value, or an error (bad name, or the appname is at its maximum). -/
inductive CResp where
  /-- English: The appname's value. -/
  | value (v : Nat)
  /-- English: The command was refused. -/
  | error
  deriving Repr, DecidableEq

/-- English: A appname name is valid when it is 1 to 64 bytes long. -/
def validName (n : Bytes) : Bool := 1 ≤ n.length && n.length ≤ 64

/-- English: The largest appname value, 2⁶⁴ − 1. An increment past it is refused. -/
def maxCount : Nat := 2 ^ 64 - 1

/-- English: The reference state: the value of every appname (0 for appnames never incremented). -/
abbrev CState := Bytes → Nat

/-- English: Set appname `n` to `v`, leaving every other appname unchanged. -/
def CState.set (s : CState) (n : Bytes) (v : Nat) : CState := fun m => if m = n then v else s m

/-- English: The reference meaning of one command: the new state and the answer. -/
def cstep (s : CState) : CCmd Bytes → CState × CResp
  | .incr n => if validName n && s n < maxCount then (s.set n (s n + 1), .value (s n + 1)) else (s, .error)
  | .get n => if validName n then (s, .value (s n)) else (s, .error)

/-! ## Storage layout in LeanKV -/

/-- English: A count stored as 8 bytes, least significant first. -/
def u64le (v : Nat) : Bytes :=
  [(v % 256).toUInt8, (v / 256 % 256).toUInt8, (v / 256 ^ 2 % 256).toUInt8,
   (v / 256 ^ 3 % 256).toUInt8, (v / 256 ^ 4 % 256).toUInt8, (v / 256 ^ 5 % 256).toUInt8,
   (v / 256 ^ 6 % 256).toUInt8, (v / 256 ^ 7 % 256).toUInt8]

/-- English: Read a stored count (least significant byte first). -/
def decodeU64 : Bytes → Nat
  | [] => 0
  | b :: bs => b.toNat + 256 * decodeU64 bs

/-- English: The appnames a LeanKV store stands for: each key's stored count, 0 if absent. -/
def dec (st : Store) : CState := fun n =>
  match st.lookup n with
  | some v => decodeU64 v
  | none => 0

/-- English: The reference translation of a command into one LeanKV command on store `st`: a
valid increment below the maximum is a `put` of the new count; everything else is a read, which
changes nothing. -/
def pickRef (st : Store) : CCmd Bytes → Cmd Bytes
  | .incr n => if validName n && dec st n < maxCount then .put n (u64le (dec st n + 1)) else .get n
  | .get n => .get n

/-! ## Spec validation (Stage 2): the layout and translation mean what the model says -/

/-- English: Reading back a stored count gives the count, for every count up to 2⁶⁴ − 1. -/
theorem decodeU64_u64le {v : Nat} (h : v < 2 ^ 64) : decodeU64 (u64le v) = v := by
  simp only [u64le, decodeU64, UInt8.toNat_ofNat', Nat.toUInt8]
  simp
  omega

/-- English: Refinement. On any well-formed store, running the translated command changes the
appnames exactly as the reference model does. -/
theorem pickRef_refines {st : Store} (hw : st.WellFormed) (c : CCmd Bytes) :
    dec (step st (pickRef st c)).1 = (cstep (dec st) c).1 := by
  cases c with
  | get n => simp only [pickRef, cstep, get_unchanged]; split <;> rfl
  | incr n =>
    simp only [pickRef, cstep]
    by_cases hv : (validName n && dec st n < maxCount) = true
    · simp only [hv, ↓reduceIte]
      have hv' : validName n = true ∧ dec st n < maxCount := by simpa using hv
      have hk : validKey n = true := by
        have := hv'.1
        simp only [validName, Bool.and_eq_true, decide_eq_true_eq] at this
        simp only [validKey, Bool.and_eq_true, decide_eq_true_eq]
        simp only [maxKeyLen]; omega
      have hval : validValue (u64le (dec st n + 1)) = true := by
        simp only [validValue, decide_eq_true_eq]; simp [u64le, maxValueLen]
      have hlt : dec st n + 1 < 2 ^ 64 := by
        have := hv'.2; simp only [maxCount] at this; omega
      rw [step_put, if_pos (by simp [hk, hval])]
      funext m
      simp only [CState.set, dec]
      by_cases hm : m = n
      · subst hm; rw [lookup_insert_self]; simp only [↓reduceIte]; exact decodeU64_u64le hlt
      · rw [lookup_insert_ne st _ hm]; simp [hm]
    · simp only [hv, Bool.false_eq_true, ↓reduceIte, get_unchanged]

end AppName.Spec
