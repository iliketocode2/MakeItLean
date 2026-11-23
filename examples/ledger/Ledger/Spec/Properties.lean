import Ledger.Spec.Model

/-!
# Ledger spec: requirement-level properties of the reference model (Stage 2)

Each main theorem restates a requirement from `REQUIREMENTS.md` as a property of `cstep`/`lrun`.
Proving them is how we check that the model means what the English says. None of them mentions
the implementation. Invariants R12/R13 are stated for ledgers reachable from the empty ledger
(REQUIREMENTS.md §4, "Scope"); `kvRun_refines` (in `Model`) shows the stored ledger is one.
-/

namespace Ledger.Spec
open LeanKV.Spec

/-! ## Definitions used to state the requirements -/

/-- English: The account names a command mentions (none for `accounts` and `total`). -/
def LCmd.names : LCmd Bytes → List Bytes
  | .openAccount n => [n]
  | .deposit n _ => [n]
  | .withdraw n _ => [n]
  | .transfer f t _ => [f, t]
  | .balance n => [n]
  | .accounts => []
  | .total => []

/-- English: A good ledger: names strictly ascending (so each name appears once, R1), every name
valid (R2), and every balance at most `maxBalance` (R3, R12). -/
def LState.Good (s : LState) : Prop :=
  s.Pairwise (fun a b => bytesLt a.1 b.1 = true) ∧
    ∀ p ∈ s, validName p.1 = true ∧ p.2 ≤ maxBalance

/-- English: Money that entered the ledger in one step: the amount of a successful deposit, else 0. -/
def flowIn : LCmd Bytes → LResp → Nat
  | .deposit _ a, .balance _ => a
  | _, _ => 0

/-- English: Money that left the ledger in one step: the amount of a successful withdrawal, else 0. -/
def flowOut : LCmd Bytes → LResp → Nat
  | .withdraw _ a, .balance _ => a
  | _, _ => 0

/-- English: Total money deposited by successful deposits in a run (commands paired with answers). -/
def inflow (cs : List (LCmd Bytes)) (rs : List LResp) : Nat :=
  ((cs.zip rs).map (fun x => flowIn x.1 x.2)).sum

/-- English: Total money withdrawn by successful withdrawals in a run (commands paired with answers). -/
def outflow (cs : List (LCmd Bytes)) (rs : List LResp) : Nat :=
  ((cs.zip rs).map (fun x => flowOut x.1 x.2)).sum

/-! ## Facts about balances in the reference state -/

/-- English: The balance of `n` in a ledger starting with pair `q` is `q`'s balance if `q` is
account `n`, and otherwise `n`'s balance in the rest. -/
theorem bal_cons (q : Bytes × Nat) (s : LState) (n : Bytes) :
    LState.bal (q :: s) n = if q.1 = n then some q.2 else LState.bal s n := by
  simp only [LState.bal, List.find?_cons]
  by_cases h : q.1 = n
  · simp [h]
  · have h' : (q.1 == n) = false := by simp [h]
    simp [h, h']

/-- English: After setting account `n` to `v`, its balance is `v`. -/
theorem bal_set_self (s : LState) (n : Bytes) (v : Nat) : (s.set n v).bal n = some v := by
  induction s with
  | nil => simp [LState.set, LState.bal]
  | cons q rest ih =>
    obtain ⟨k', v'⟩ := q
    simp only [LState.set]
    by_cases h1 : bytesLt n k' = true
    · simp [h1, LState.bal]
    · by_cases h2 : (n == k') = true
      · simp [h1, h2, LState.bal]
      · have hk : k' ≠ n := fun e => by subst e; simp at h2
        simp only [h1, h2, Bool.false_eq_true, ↓reduceIte, bal_cons, hk, ih]

/-- English: Setting account `n` leaves every other account's balance unchanged. -/
theorem bal_set_ne (s : LState) {n m : Bytes} (v : Nat) (h : m ≠ n) :
    (s.set n v).bal m = s.bal m := by
  induction s with
  | nil => simp [LState.set, LState.bal, Ne.symm h]
  | cons q rest ih =>
    obtain ⟨k', v'⟩ := q
    simp only [LState.set]
    by_cases h1 : bytesLt n k' = true
    · simp [h1, LState.bal, Ne.symm h]
    · by_cases h2 : (n == k') = true
      · have e : n = k' := by simpa using h2
        subst e
        simp [h1, LState.bal, Ne.symm h]
      · simp only [h1, h2, Bool.false_eq_true, ↓reduceIte]
        simp only [LState.bal, List.find?_cons] at ih ⊢
        split <;> simp_all

/-- English: Setting a list of accounts leaves every account not in the list unchanged. -/
theorem bal_setAll_notin (s : LState) (ups : List (Bytes × Nat)) {m : Bytes}
    (h : m ∉ ups.map Prod.fst) : (s.setAll ups).bal m = s.bal m := by
  induction ups generalizing s with
  | nil => rfl
  | cons p ups ih =>
    simp only [List.map_cons, List.mem_cons, not_or] at h
    simp only [LState.setAll, List.foldl_cons] at ih ⊢
    rw [ih _ h.2, bal_set_ne _ _ h.1]

/-- English: A balance found in a ledger is the balance of one of its pairs. -/
theorem mem_of_bal {s : LState} {n : Bytes} {b : Nat} (h : s.bal n = some b) : (n, b) ∈ s := by
  simp only [LState.bal, Option.map_eq_some_iff] at h
  obtain ⟨p, hp, rfl⟩ := h
  have hm := List.mem_of_find?_eq_some hp
  have hk := List.find?_some hp
  simp only [beq_iff_eq] at hk
  subst hk; exact hm

/-- English: Every pair of a ledger after a set is an old pair or the new one. -/
theorem mem_set {s : LState} {k : Bytes} {v : Nat} {p : Bytes × Nat} (h : p ∈ s.set k v) :
    p ∈ s ∨ p = (k, v) := by
  induction s with
  | nil => simp [LState.set] at h; exact .inr h
  | cons q rest ih =>
    obtain ⟨k', v'⟩ := q
    simp only [LState.set] at h
    split at h
    · simp only [List.mem_cons] at h ⊢; rcases h with h | h | h <;> simp_all
    · split at h
      · simp only [List.mem_cons] at h ⊢; rcases h with h | h <;> simp_all
      · simp only [List.mem_cons] at h ⊢
        rcases h with h | h
        · exact .inl (.inl h)
        · rcases ih h with h' | h'
          · exact .inl (.inr h')
          · exact .inr h'

/-- English: Setting a balance keeps the names in strictly ascending order. -/
theorem set_sorted {s : LState} (hs : s.Pairwise (fun a b => bytesLt a.1 b.1 = true))
    (k : Bytes) (v : Nat) : (s.set k v).Pairwise (fun a b => bytesLt a.1 b.1 = true) := by
  induction s with
  | nil => simp [LState.set]
  | cons q rest ih =>
    obtain ⟨k', v'⟩ := q
    rw [List.pairwise_cons] at hs
    obtain ⟨h1, h2⟩ := hs
    simp only [LState.set]
    by_cases hlt : bytesLt k k' = true
    · simp only [hlt, ↓reduceIte]
      refine List.Pairwise.cons ?_ (List.Pairwise.cons h1 h2)
      intro x hx
      simp only [List.mem_cons] at hx
      rcases hx with rfl | hx
      · exact hlt
      · exact bytesLt_trans hlt (h1 x hx)
    · by_cases heq : (k == k') = true
      · have e : k = k' := by simpa using heq
        subst e
        simp only [hlt, heq, ↓reduceIte, Bool.false_eq_true]
        exact List.Pairwise.cons h1 h2
      · simp only [hlt, heq, Bool.false_eq_true, ↓reduceIte]
        refine List.Pairwise.cons ?_ (ih h2)
        intro x hx
        rcases mem_set hx with hx | rfl
        · exact h1 x hx
        · have hne : k ≠ k' := fun e => by subst e; simp at heq
          rcases bytesLt_total hne with h | h
          · simp_all
          · exact h

/-- English: In a ledger with ascending names, an account smaller than the first name is absent. -/
theorem bal_none_of_lt {rest : LState} {k' n : Bytes}
    (h1 : ∀ x ∈ rest, bytesLt k' x.1 = true) (hlt : bytesLt n k' = true) : rest.bal n = none := by
  simp only [LState.bal, Option.map_eq_none_iff, List.find?_eq_none, beq_iff_eq]
  intro x hx e
  have := bytesLt_trans hlt (h1 x hx)
  rw [e, bytesLt_irrefl] at this
  simp at this

/-- English: Setting account `n` to `v` changes the total by replacing `n`'s old balance (0 if
there was no account) with `v`. -/
theorem total_set {s : LState} (hs : s.Pairwise (fun a b => bytesLt a.1 b.1 = true))
    (n : Bytes) (v : Nat) : (s.set n v).total + (s.bal n).getD 0 = s.total + v := by
  induction s with
  | nil => simp [LState.set, LState.total, LState.bal]
  | cons q rest ih =>
    obtain ⟨k', v'⟩ := q
    rw [List.pairwise_cons] at hs
    obtain ⟨h1, h2⟩ := hs
    simp only [LState.set]
    by_cases hlt : bytesLt n k' = true
    · have hne : k' ≠ n := fun e => by subst e; rw [bytesLt_irrefl] at hlt; simp at hlt
      have hb : LState.bal ((k', v') :: rest) n = none := by
        rw [bal_cons]; simp only [hne, ↓reduceIte]
        exact bal_none_of_lt h1 hlt
      simp only [hlt, ↓reduceIte, hb, LState.total, List.map_cons, List.sum_cons,
        Option.getD_none]
      omega
    · by_cases heq : (n == k') = true
      · have e : n = k' := by simpa using heq
        subst e
        simp [hlt, LState.total, LState.bal]
        omega
      · have hne : k' ≠ n := fun e => by subst e; simp at heq
        have hb : LState.bal ((k', v') :: rest) n = LState.bal rest n := by
          rw [bal_cons]; simp [hne]
        have := ih h2
        simp only [hlt, heq, Bool.false_eq_true, ↓reduceIte, hb, LState.total, List.map_cons,
          List.sum_cons] at this ⊢
        omega

/-- English: Every balance in a good ledger is at most `maxBalance`. -/
theorem LState.Good.bal_le {s : LState} (hs : s.Good) {n : Bytes} {b : Nat} (h : s.bal n = some b) :
    b ≤ maxBalance := (hs.2 _ (mem_of_bal h)).2

/-- English: Setting a valid name to a balance at most `maxBalance` keeps a ledger good. -/
theorem LState.Good.set {s : LState} (hs : s.Good) {k : Bytes} {v : Nat} (hk : validName k = true)
    (hv : v ≤ maxBalance) : (s.set k v).Good := by
  refine ⟨set_sorted hs.1 k v, fun p hp => ?_⟩
  rcases mem_set hp with hp | rfl
  · exact hs.2 p hp
  · exact ⟨hk, hv⟩

/-- English: Applying valid settings keeps a ledger good. -/
theorem LState.Good.setAll {s : LState} (hs : s.Good) {ups : List (Bytes × Nat)}
    (h : ∀ p ∈ ups, validName p.1 = true ∧ p.2 ≤ maxBalance) : (s.setAll ups).Good := by
  induction ups generalizing s with
  | nil => exact hs
  | cons p ups ih =>
    simp only [LState.setAll, List.foldl_cons] at ih ⊢
    have hp := h p (by simp)
    exact ih (hs.set hp.1 hp.2) (fun q hq => h q (by simp [hq]))

/-! ## R12: balances stay between 0 and `maxBalance` -/

/-- English: The new, empty ledger is good. -/
theorem good_empty : LState.Good [] := ⟨List.Pairwise.nil, fun _ h => by simp at h⟩

/-- English: Every command keeps a good ledger good (R12). -/
theorem cstep_good {s : LState} (hs : s.Good) (c : LCmd Bytes) : (cstep s c).1.Good := by
  unfold cstep
  cases hp : plan s.bal c with
  | write ups r =>
    exact hs.setAll (plan_write_ok (Nat.le_refl _) (fun _ _ h => hs.bal_le h) hp).1
  | _ => exact hs

/-- English: Running commands keeps a good ledger good. -/
theorem lrun_good (cs : List (LCmd Bytes)) {s : LState} (hs : s.Good) : (lrun s cs).1.Good := by
  induction cs generalizing s with
  | nil => exact hs
  | cons c cs ih => exact ih (cstep_good hs c)

/-- English: **R12.** In every ledger reachable from the empty ledger, every account's balance is
at most `maxBalance` (and, being a natural number, never negative), and names are unique and
valid. -/
theorem reachable_good (cs : List (LCmd Bytes)) : (lrun [] cs).1.Good := lrun_good cs good_empty

/-- English: **R12, as a bound.** In every reachable ledger, every balance is at most
`maxBalance`. -/
theorem reachable_bal_le (cs : List (LCmd Bytes)) {n : Bytes} {b : Nat}
    (h : (lrun [] cs).1.bal n = some b) : b ≤ maxBalance := (reachable_good cs).bal_le h

/-! ## R11: all-or-nothing -/

/-- English: **R11.** A refused command changes nothing. -/
theorem refused_unchanged (s : LState) (c : LCmd Bytes) {e : LErr} (h : (cstep s c).2 = .err e) :
    (cstep s c).1 = s := by
  unfold cstep at h ⊢
  cases hp : plan s.bal c with
  | write ups r =>
    rw [hp] at h
    rcases plan_write_cases hp with ⟨_, _, _, _, _, rfl⟩ | ⟨_, _, _, _, _, _, _, _, _, rfl⟩ |
      ⟨_, _, _, _, _, _, _, _, _, rfl⟩ | ⟨_, _, _, _, _, _, _, _, _, _, _, _, _, _, _, rfl⟩ <;>
      simp at h
  | _ => rfl

/-- English: **R11.** A command changes only the accounts it names: every other account keeps its
balance (or stays absent). -/
theorem only_named_change (s : LState) (c : LCmd Bytes) {m : Bytes} (h : m ∉ c.names) :
    (cstep s c).1.bal m = s.bal m := by
  unfold cstep
  cases hp : plan s.bal c with
  | write ups r =>
    simp only
    apply bal_setAll_notin
    rcases plan_write_cases hp with ⟨n, rfl, _, _, rfl, _⟩ | ⟨n, a, b, rfl, _, _, _, _, rfl, _⟩ |
      ⟨n, a, b, rfl, _, _, _, _, rfl, _⟩ | ⟨f, t, a, bf, bt, rfl, _, _, _, _, _, _, _, _, rfl, _⟩ <;>
      simpa [LCmd.names] using h
  | _ => rfl

/-- English: **R10, R10a, R10b.** `balance`, `accounts` and `total` never change the ledger. -/
theorem reads_unchanged (s : LState) (n : Bytes) :
    (cstep s (.balance n)).1 = s ∧ (cstep s .accounts).1 = s ∧ (cstep s .total).1 = s := by
  refine ⟨?_, rfl, rfl⟩
  unfold cstep
  cases hp : plan s.bal (.balance n) with
  | write ups r => rcases plan_write_cases hp with ⟨_, h, _⟩ | ⟨_, _, _, h, _⟩ | ⟨_, _, _, h, _⟩ |
      ⟨_, _, _, _, _, h, _⟩ <;> cases h
  | _ => rfl

/-! ## The effect of each successful command (R6–R9) -/

/-- English: A command makes an answer-only plan only for `balance n` of an existing account,
answering its balance. -/
theorem plan_answer_cases {look : Bytes → Option Nat} {c : LCmd Bytes} {r : LResp}
    (h : plan look c = .answer r) : ∃ n b, c = .balance n ∧ look n = some b ∧ r = .balance b := by
  cases c <;> simp only [plan] at h <;> (repeat' split at h) <;>
    first | (cases h; exact ⟨_, _, rfl, by assumption, rfl⟩) | cases h

/-- English: Only `accounts` makes the list-all plan. -/
theorem plan_listAll {look : Bytes → Option Nat} {c : LCmd Bytes} (h : plan look c = .listAll) :
    c = .accounts := by
  cases c <;> simp only [plan] at h <;> (repeat' split at h) <;> first | rfl | cases h

/-- English: Only `total` makes the sum-all plan. -/
theorem plan_sumAll {look : Bytes → Option Nat} {c : LCmd Bytes} (h : plan look c = .sumAll) :
    c = .total := by
  cases c <;> simp only [plan] at h <;> (repeat' split at h) <;> first | rfl | cases h

/-- English: **R6.** A successful `open n` creates account `n` with balance 0; it was absent
before. -/
theorem open_ok (s : LState) (n : Bytes) (h : (cstep s (.openAccount n)).2 = .ok) :
    s.bal n = none ∧ (cstep s (.openAccount n)).1.bal n = some 0 := by
  unfold cstep at h ⊢
  cases hp : plan s.bal (.openAccount n) with
  | write ups r =>
    rcases plan_write_cases hp with ⟨n', he, _, hb, rfl, rfl⟩ | ⟨_, _, _, he, _⟩ |
      ⟨_, _, _, he, _⟩ | ⟨_, _, _, _, _, he, _⟩ <;> cases he
    exact ⟨hb, by simp [LState.setAll, bal_set_self]⟩
  | refuse e => rw [hp] at h; simp at h
  | answer r => obtain ⟨_, _, he, _⟩ := plan_answer_cases hp; cases he
  | listAll => have := plan_listAll hp; cases this
  | sumAll => have := plan_sumAll hp; cases this

/-- English: **R7.** A successful `deposit n a` answers the new balance, which is the old balance
plus `a`. -/
theorem deposit_ok (s : LState) (n : Bytes) (a b : Nat)
    (h : (cstep s (.deposit n a)).2 = .balance b) :
    ∃ b0, s.bal n = some b0 ∧ b = b0 + a ∧ (cstep s (.deposit n a)).1.bal n = some b := by
  unfold cstep at h ⊢
  cases hp : plan s.bal (.deposit n a) with
  | write ups r =>
    rw [hp] at h
    rcases plan_write_cases hp with ⟨_, he, _⟩ | ⟨n', a', b0, he, _, _, hb, _, rfl, rfl⟩ |
      ⟨_, _, _, he, _⟩ | ⟨_, _, _, _, _, he, _⟩ <;> cases he
    simp only [LResp.balance.injEq] at h
    exact ⟨b0, hb, h.symm, by simp [LState.setAll, bal_set_self, h]⟩
  | refuse e => rw [hp] at h; simp at h
  | answer r => obtain ⟨_, _, he, _⟩ := plan_answer_cases hp; cases he
  | listAll => have := plan_listAll hp; cases this
  | sumAll => have := plan_sumAll hp; cases this

/-- English: **R8.** A successful `withdraw n a` answers the new balance, which is the old balance
minus `a`, and the old balance was at least `a`. -/
theorem withdraw_ok (s : LState) (n : Bytes) (a b : Nat)
    (h : (cstep s (.withdraw n a)).2 = .balance b) :
    ∃ b0, s.bal n = some b0 ∧ a ≤ b0 ∧ b = b0 - a ∧ (cstep s (.withdraw n a)).1.bal n = some b := by
  unfold cstep at h ⊢
  cases hp : plan s.bal (.withdraw n a) with
  | write ups r =>
    rw [hp] at h
    rcases plan_write_cases hp with ⟨_, he, _⟩ | ⟨_, _, _, he, _⟩ |
      ⟨n', a', b0, he, _, _, hb, hab, rfl, rfl⟩ | ⟨_, _, _, _, _, he, _⟩ <;> cases he
    simp only [LResp.balance.injEq] at h
    exact ⟨b0, hb, hab, h.symm, by simp [LState.setAll, bal_set_self, h]⟩
  | refuse e => rw [hp] at h; simp at h
  | answer r => obtain ⟨_, _, he, _⟩ := plan_answer_cases hp; cases he
  | listAll => have := plan_listAll hp; cases this
  | sumAll => have := plan_sumAll hp; cases this

/-- English: **R8, never negative.** A withdrawal of more than the balance is refused with
`INSUFFICIENT_FUNDS` (for a valid name and amount), so it never takes a balance below 0. -/
theorem withdraw_too_much (s : LState) (n : Bytes) (a b0 : Nat) (hn : validName n = true)
    (ha : validAmount a = true) (hb : s.bal n = some b0) (hlt : b0 < a) :
    cstep s (.withdraw n a) = (s, .err .insufficientFunds) := by
  have : ¬ a ≤ b0 := by omega
  simp [cstep, plan, hn, ha, hb, this]

/-- English: **R9.** A successful `transfer f t a` takes `a` from `f` (which held at least `a`) and
adds `a` to `t`, in one step; `f` and `t` are different existing accounts. -/
theorem transfer_ok (s : LState) (f t : Bytes) (a : Nat) (h : (cstep s (.transfer f t a)).2 = .ok) :
    ∃ bf bt, f ≠ t ∧ s.bal f = some bf ∧ s.bal t = some bt ∧ a ≤ bf ∧
      (cstep s (.transfer f t a)).1.bal f = some (bf - a) ∧
      (cstep s (.transfer f t a)).1.bal t = some (bt + a) := by
  unfold cstep at h ⊢
  cases hp : plan s.bal (.transfer f t a) with
  | write ups r =>
    rcases plan_write_cases hp with ⟨_, he, _⟩ | ⟨_, _, _, he, _⟩ | ⟨_, _, _, he, _⟩ |
      ⟨f', t', a', bf, bt, he, _, _, hne, _, hf, ht, hab, _, rfl, rfl⟩ <;> cases he
    refine ⟨bf, bt, hne, hf, ht, hab, ?_, ?_⟩
    · simp only [LState.setAll, List.foldl_cons, List.foldl_nil]
      rw [bal_set_ne _ _ hne, bal_set_self]
    · simp [LState.setAll, bal_set_self]
  | refuse e => rw [hp] at h; simp at h
  | answer r => obtain ⟨_, _, he, _⟩ := plan_answer_cases hp; cases he
  | listAll => have := plan_listAll hp; cases this
  | sumAll => have := plan_sumAll hp; cases this

/-- English: **R9, never negative.** A transfer of more than the source balance is refused with
`INSUFFICIENT_FUNDS` (for valid, different, existing accounts and a valid amount). -/
theorem transfer_too_much (s : LState) (f t : Bytes) (a bf bt : Nat) (hf : validName f = true)
    (ht : validName t = true) (hne : f ≠ t) (ha : validAmount a = true) (hbf : s.bal f = some bf)
    (hbt : s.bal t = some bt) (hlt : bf < a) :
    cstep s (.transfer f t a) = (s, .err .insufficientFunds) := by
  have : ¬ a ≤ bf := by omega
  simp [cstep, plan, hf, ht, hne, ha, hbf, hbt, this]

/-! ## R13: conservation of money -/

/-- English: **R13, one step.** On a good ledger, every command changes the total by exactly the
money it brings in or takes out: a successful deposit of `a` adds `a`, a successful withdrawal of
`a` removes `a`, and every other command (including every transfer) leaves the total unchanged. -/
theorem cstep_total {s : LState} (hs : s.Good) (c : LCmd Bytes) :
    (cstep s c).1.total + flowOut c (cstep s c).2 = s.total + flowIn c (cstep s c).2 := by
  unfold cstep
  cases hp : plan s.bal c with
  | write ups r =>
    rcases plan_write_cases hp with ⟨n, rfl, hn, hb, rfl, rfl⟩ |
      ⟨n, a, b, rfl, hn, _, hb, _, rfl, rfl⟩ | ⟨n, a, b, rfl, hn, _, hb, hab, rfl, rfl⟩ |
      ⟨f, t, a, bf, bt, rfl, hf, ht, hne, _, hbf, hbt, hab, _, rfl, rfl⟩
    · have := total_set hs.1 n 0
      simp only [hb, Option.getD_none] at this
      simp only [LState.setAll, List.foldl_cons, List.foldl_nil, flowIn, flowOut]; omega
    · have := total_set hs.1 n (b + a)
      simp only [hb, Option.getD_some] at this
      simp only [LState.setAll, List.foldl_cons, List.foldl_nil, flowIn, flowOut]; omega
    · have := total_set hs.1 n (b - a)
      simp only [hb, Option.getD_some] at this
      simp only [LState.setAll, List.foldl_cons, List.foldl_nil, flowIn, flowOut]; omega
    · have e1 := total_set hs.1 f (bf - a)
      have e2 := total_set (set_sorted hs.1 f (bf - a)) t (bt + a)
      rw [bal_set_ne _ _ (Ne.symm hne), hbt] at e2
      simp only [hbf, Option.getD_some] at e1 e2
      simp only [LState.setAll, List.foldl_cons, List.foldl_nil, flowIn, flowOut]; omega
  | refuse e => cases c <;> simp [flowIn, flowOut]
  | answer r =>
    obtain ⟨n, _, rfl, _, rfl⟩ := plan_answer_cases hp
    simp [flowIn, flowOut]
  | listAll => rw [plan_listAll hp]; simp [flowIn, flowOut]
  | sumAll => rw [plan_sumAll hp]; simp [flowIn, flowOut]

/-- English: **R13, transfers.** On a good ledger, a transfer never changes the total, whether it
succeeds or is refused. -/
theorem transfer_conserves {s : LState} (hs : s.Good) (f t : Bytes) (a : Nat) :
    (cstep s (.transfer f t a)).1.total = s.total := by
  have := cstep_total hs (.transfer f t a)
  simp only [flowIn, flowOut] at this
  omega

/-- English: **R13, whole runs.** From a good ledger, after any sequence of commands, the total
plus everything withdrawn equals the starting total plus everything deposited. -/
theorem lrun_total (cs : List (LCmd Bytes)) {s : LState} (hs : s.Good) :
    (lrun s cs).1.total + outflow cs (lrun s cs).2 = s.total + inflow cs (lrun s cs).2 := by
  induction cs generalizing s with
  | nil => simp [lrun, outflow, inflow]
  | cons c cs ih =>
    have h1 := cstep_total hs c
    have h2 := ih (cstep_good hs c)
    simp only [lrun, outflow, inflow, List.zip_cons_cons, List.map_cons, List.sum_cons] at h2 ⊢
    omega

/-- English: **R13, from a new ledger.** After any sequence of commands on the empty ledger, the
total plus the sum of successful withdrawals equals the sum of successful deposits; that is,
total = deposits − withdrawals. -/
theorem reachable_total (cs : List (LCmd Bytes)) :
    (lrun [] cs).1.total + outflow cs (lrun [] cs).2 = inflow cs (lrun [] cs).2 := by
  have := lrun_total cs good_empty
  simpa [LState.total] using this

/-! ## Examples from REQUIREMENTS.md §3 (executable checks) -/

/-- English: The bytes of a text (ASCII names in the examples). -/
def nm (s : String) : Bytes := s.toUTF8.toList

/-- English: The 18-step example script of REQUIREMENTS.md §3. -/
def exampleScript : List (LCmd Bytes) :=
  [.openAccount (nm "alice"), .openAccount (nm "alice"), .openAccount (nm "bob"),
   .deposit (nm "alice") 1000, .transfer (nm "alice") (nm "bob") 300, .balance (nm "alice"),
   .balance (nm "bob"), .transfer (nm "bob") (nm "alice") 301, .transfer (nm "alice") (nm "carol") 1,
   .transfer (nm "alice") (nm "bob") 0, .transfer (nm "alice") (nm "alice") 5, .withdraw (nm "bob") 300,
   .withdraw (nm "bob") 1, .deposit (nm "carol") 5, .openAccount (nm "bad/name"),
   .deposit (nm "alice") 9223372036854775807, .accounts, .total]

/-- English: The answers REQUIREMENTS.md §3 expects for the example script, in order. -/
def exampleAnswers : List LResp :=
  [.ok, .err .accountExists, .ok, .balance 1000, .ok, .balance 700, .balance 300,
   .err .insufficientFunds, .err (.unknownAccount (nm "carol")), .err .badAmount, .err .sameAccount,
   .balance 0, .err .insufficientFunds, .err (.unknownAccount (nm "carol")), .err .badName,
   .err .balanceLimit, .accounts [(nm "alice", 700), (nm "bob", 0)], .total 700]

#guard (lrun [] exampleScript).2 == exampleAnswers

-- Error order (§3): the first applicable error is reported.
#guard (cstep [] (.transfer (nm "x") (nm "x") 0)).2 == .err .sameAccount
#guard (cstep [] (.transfer (nm "x") (nm "y") 0)).2 == .err .badAmount
#guard (cstep [] (.transfer (nm "x") (nm "y") 5)).2 == .err (.unknownAccount (nm "x"))
#guard (cstep [(nm "x", 9)] (.transfer (nm "x") (nm "y") 5)).2 == .err (.unknownAccount (nm "y"))
#guard (cstep [(nm "x", 4), (nm "y", 0)] (.transfer (nm "x") (nm "y") 5)).2 == .err .insufficientFunds
#guard (cstep [(nm "x", 9), (nm "y", maxBalance)] (.transfer (nm "x") (nm "y") 5)).2 == .err .balanceLimit
#guard (cstep [] (.deposit (nm "") 5)).2 == .err .badName
#guard (cstep [] (.deposit (nm "x") (maxBalance + 1))).2 == .err .badAmount
-- Limits: names of 64 and 65 bytes; amounts 1 and MAX.
#guard (cstep [] (.openAccount (List.replicate 64 0x61))).2 == .ok
#guard (cstep [] (.openAccount (List.replicate 65 0x61))).2 == .err .badName
#guard (cstep [(nm "x", 0)] (.deposit (nm "x") maxBalance)).2 == .balance maxBalance
#guard (cstep [(nm "x", 0)] (.deposit (nm "x") 1)).2 == .balance 1
-- Names are case-sensitive and ordered bytewise ("B" < "a").
#guard (lrun [] [.openAccount (nm "a"), .openAccount (nm "B"), .openAccount (nm "A"), .accounts]).2.getLast? ==
  some (.accounts [(nm "A", 0), (nm "B", 0), (nm "a", 0)])
-- The stored layout: the example run through LeanKV decodes to the model's ledger.
#guard dec (kvRun [] exampleScript) == (lrun [] exampleScript).1

end Ledger.Spec
