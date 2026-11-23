import Counter.Spec.Model

/-!
# Counter spec: requirement-level properties and examples

The reference model's behaviour, stated as theorems a reviewer can check against REQUIREMENTS.md,
plus the requirements' worked examples as executable checks (`#guard`). Proven at Stage 2.
-/

namespace Counter.Spec
open LeanKV.Spec

/-- English: Run commands from a state with the reference model: the final state and every answer. -/
def crun (s : CState) : List (CCmd Bytes) → CState × List CResp
  | [] => (s, [])
  | c :: cs => let (s', r) := cstep s c; let (s'', rs) := crun s' cs; (s'', r :: rs)

/-- English: The empty state: every counter is 0. -/
def CState.empty : CState := fun _ => 0

/-- English: Reading a counter changes nothing. -/
theorem get_unchanged_model (s : CState) (n : Bytes) : (cstep s (.get n)).1 = s := by
  simp only [cstep]; split <;> rfl

/-- English: An increment of a valid counter below the maximum answers the old value plus one. -/
theorem incr_answers (s : CState) (n : Bytes) (hv : validName n = true) (hm : s n < maxCount) :
    (cstep s (.incr n)).2 = .value (s n + 1) := by
  simp [cstep, hv, hm]

/-- English: A step keeps every counter at most the maximum. -/
theorem cstep_bounded {s : CState} (hs : ∀ m, s m ≤ maxCount) (c : CCmd Bytes) :
    ∀ m, (cstep s c).1 m ≤ maxCount := by
  intro m
  cases c with
  | get n => simp only [cstep]; split <;> exact hs m
  | incr n =>
    simp only [cstep]
    split
    · rename_i h
      simp only [Bool.and_eq_true, decide_eq_true_eq] at h
      simp only [CState.set]; split
      · subst_vars; omega
      · exact hs m
    · exact hs m

/-- English: Every counter reachable from the empty state is at most the maximum. -/
theorem reachable_bounded (cs : List (CCmd Bytes)) (m : Bytes) : (crun CState.empty cs).1 m ≤ maxCount := by
  suffices h : ∀ (cs : List (CCmd Bytes)) (s : CState), (∀ m, s m ≤ maxCount) → ∀ m, (crun s cs).1 m ≤ maxCount from
    h cs _ (fun _ => by simp [CState.empty]) m
  intro cs
  induction cs with
  | nil => intro s hs m; exact hs m
  | cons c cs ih => intro s hs m; exact ih _ (cstep_bounded hs c) m

/-! ## Worked examples (REQUIREMENTS.md), checked at build time -/

/-- English: The bytes of a text (ASCII names in the examples). -/
def nm (s : String) : Bytes := s.toUTF8.toList

-- incr, incr, get on one counter; another counter is untouched.
#guard (crun CState.empty [.incr (nm "a"), .incr (nm "a"), .get (nm "a"), .get (nm "b")]).2 ==
  [.value 1, .value 2, .value 2, .value 0]
-- Names of 0 and 65 bytes are refused; 64 bytes is fine.
#guard (cstep CState.empty (.incr [])).2 == .error
#guard (cstep CState.empty (.incr (List.replicate 65 0x61))).2 == .error
#guard (cstep CState.empty (.incr (List.replicate 64 0x61))).2 == .value 1
-- At the maximum, an increment is refused and changes nothing.
#guard (cstep (fun _ => maxCount) (.incr (nm "a"))).2 == .error
-- The stored layout: a counter written through LeanKV reads back as the model's value.
#guard dec (step [] (pickRef [] (.incr (nm "a")))).1 (nm "a") == 1

end Counter.Spec
