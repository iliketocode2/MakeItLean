import LeanKV.Spec.Model

/-!
# LeanKV spec: requirement-level properties of the reference model

Each main theorem restates a requirement from `REQUIREMENTS.md` as a property of the reference
model `step`. Proving them (Stage 2) is how we check that the model means what the English
says. None of them mentions an implementation. The smaller lemmas in between are proof steps;
each also carries its English meaning.
-/

namespace LeanKV.Spec

/-- English: A store is well-formed when its keys are strictly ascending and every key and
value is within the R1 limits. -/
def Store.WellFormed (s : Store) : Prop :=
  s.Pairwise (fun a b => bytesLt a.1 b.1 = true) ∧
    ∀ p ∈ s, validKey p.1 = true ∧ validValue p.2 = true

/-- English: The single-command form of a write: `put k v` or `delete k`. -/
def WriteOp.toCmd {β : Type} : WriteOp β → Cmd β
  | .put k v => .put k v
  | .delete k => .delete k

/-- English: Looking up a key means finding the first pair with that key and taking its value. -/
theorem lookup_eq (s : Store) (k : Bytes) : s.lookup k = (s.find? (fun p => p.1 == k)).map Prod.snd := by
  unfold Store.lookup; split <;> next h => simp [h]

/-- English: Looking up a key in a list that starts with pair q gives q's value if q has that key, and otherwise looks in the rest. -/
theorem lookup_cons (q : Bytes × Bytes) (s : Store) (k : Bytes) :
    Store.lookup (q :: s) k = if q.1 = k then some q.2 else s.lookup k := by
  simp only [lookup_eq, List.find?_cons]; split <;> simp_all

/-- English: After inserting key k with value v, looking up k gives v. -/
theorem lookup_insert_self (s : Store) (k v : Bytes) : (s.insert k v).lookup k = some v := by
  induction s with
  | nil => simp [Store.insert, lookup_cons]
  | cons q rest ih =>
    obtain ⟨k', v'⟩ := q
    simp only [Store.insert]
    split
    · simp [lookup_cons]
    · split
      · simp [lookup_cons]
      · rename_i h1 h2
        have : k' ≠ k := fun e => by simp_all
        simp [lookup_cons, this, ih]

/-- English: Inserting key k does not change the lookup of any other key. -/
theorem lookup_insert_ne (s : Store) {k k'' : Bytes} (v : Bytes) (hne : k'' ≠ k) :
    (s.insert k v).lookup k'' = s.lookup k'' := by
  induction s with
  | nil => simp [Store.insert, Ne.symm hne, Store.lookup]
  | cons q rest ih =>
    obtain ⟨k', v'⟩ := q
    simp only [Store.insert]
    split
    · simp [lookup_cons, Ne.symm hne]
    · split
      · rename_i h1 h2
        have : k = k' := by simpa using h2
        subst this
        simp [lookup_cons, Ne.symm hne]
      · simp [lookup_cons, ih]

/-- English: After erasing key k, looking up k finds nothing. -/
theorem lookup_erase_self (s : Store) (k : Bytes) : (s.erase k).lookup k = none := by
  induction s with
  | nil => rfl
  | cons q rest ih =>
    simp only [Store.erase, List.filter_cons] at *
    split
    · rename_i h
      have : q.1 ≠ k := by simpa using h
      simp [lookup_cons, this, ih]
    · exact ih

/-- English: Erasing key k does not change the lookup of any other key. -/
theorem lookup_erase_ne (s : Store) {k k'' : Bytes} (hne : k'' ≠ k) :
    (s.erase k).lookup k'' = s.lookup k'' := by
  induction s with
  | nil => rfl
  | cons q rest ih =>
    simp only [Store.erase, List.filter_cons] at *
    split
    · simp [lookup_cons, ih]
    · rename_i h
      have : q.1 = k := by simpa using h
      subst this
      simp [lookup_cons, Ne.symm hne, ih]

/-- English: Erasing a key that is not present leaves the store exactly as it was. -/
theorem erase_of_lookup_none {s : Store} {k : Bytes} (h : s.lookup k = none) : s.erase k = s := by
  induction s with
  | nil => rfl
  | cons q rest ih =>
    rw [lookup_cons] at h
    split at h
    · simp at h
    · rename_i hq
      have e : Store.erase (q :: rest) k = q :: Store.erase rest k := by
        simp [Store.erase, hq]
      rw [e, ih h]

/-- English: No key is smaller than itself (R2). -/
theorem bytesLt_irrefl (a : Bytes) : bytesLt a a = false := by
  induction a with
  | nil => rfl
  | cons x xs ih => simp [bytesLt, ih]

/-- English: If a < b and b < c then a < c (R2). -/
theorem bytesLt_trans {a b c : Bytes} (hab : bytesLt a b = true) (hbc : bytesLt b c = true) :
    bytesLt a c = true := by
  induction a generalizing b c with
  | nil => cases b <;> cases c <;> simp_all [bytesLt]
  | cons x xs ih =>
    cases b with
    | nil => simp [bytesLt] at hab
    | cons y ys =>
      cases c with
      | nil => simp [bytesLt] at hbc
      | cons z zs =>
        simp only [bytesLt, Bool.or_eq_true, decide_eq_true_eq, Bool.and_eq_true, beq_iff_eq] at *
        rcases hab with h1 | ⟨rfl, h1⟩ <;> rcases hbc with h2 | ⟨rfl, h2⟩
        · exact Or.inl (UInt8.lt_trans h1 h2)
        · exact Or.inl h1
        · exact Or.inl h2
        · exact Or.inr ⟨rfl, ih h1 h2⟩

/-- English: Any two different keys are ordered one way or the other (R2). -/
theorem bytesLt_total {a b : Bytes} (h : a ≠ b) : bytesLt a b = true ∨ bytesLt b a = true := by
  induction a generalizing b with
  | nil => cases b <;> simp_all [bytesLt]
  | cons x xs ih =>
    cases b with
    | nil => simp [bytesLt]
    | cons y ys =>
      simp only [bytesLt, Bool.or_eq_true, decide_eq_true_eq, Bool.and_eq_true, beq_iff_eq]
      by_cases hxy : x = y
      · subst hxy
        have : xs ≠ ys := fun e => h (by rw [e])
        rcases ih this with h1 | h1
        · exact Or.inl (Or.inr ⟨rfl, h1⟩)
        · exact Or.inr (Or.inr ⟨rfl, h1⟩)
      · rcases UInt8.lt_or_lt_of_ne hxy with h1 | h1
        · exact Or.inl (Or.inl h1)
        · exact Or.inr (Or.inl h1)

/-- English: Every pair after an insert is either the inserted pair or a pair that was already there. -/
theorem mem_insert {s : Store} {k v : Bytes} {p : Bytes × Bytes} (h : p ∈ s.insert k v) :
    p = (k, v) ∨ p ∈ s := by
  induction s with
  | nil => simp_all [Store.insert]
  | cons q rest ih =>
    obtain ⟨k', v'⟩ := q
    simp only [Store.insert] at h
    split at h
    · simp at h; rcases h with h | h | h <;> simp_all
    · split at h
      · simp at h; rcases h with h | h <;> simp_all
      · simp at h; rcases h with h | h
        · simp_all
        · rcases ih h with h' | h' <;> simp_all

/-- English: Inserting a valid key and value keeps a store well-formed. -/
theorem insert_wf {s : Store} (hs : s.WellFormed) {k v : Bytes} (hk : validKey k = true)
    (hv : validValue v = true) : Store.WellFormed (s.insert k v) := by
  induction s with
  | nil => simp_all [Store.WellFormed, Store.insert]
  | cons q rest ih =>
    obtain ⟨k', v'⟩ := q
    obtain ⟨hp, hval⟩ := hs
    rw [List.pairwise_cons] at hp
    have ihr := ih ⟨hp.2, fun p hp' => hval p (List.mem_cons_of_mem _ hp')⟩
    simp only [Store.insert]
    split
    · rename_i hlt
      refine ⟨?_, ?_⟩
      · refine List.Pairwise.cons ?_ (List.Pairwise.cons hp.1 hp.2)
        intro a ha
        simp at ha
        rcases ha with ha | ha
        · simp_all
        · exact bytesLt_trans hlt (hp.1 a ha)
      · intro p hp'; simp at hp'; rcases hp' with h | h | h
        · simp_all
        · simpa [h] using hval (k', v') (by simp)
        · exact hval p (List.mem_cons_of_mem _ h)
    · split
      · rename_i _ heq
        have : k = k' := by simpa using heq
        subst this
        refine ⟨List.Pairwise.cons (fun a ha => hp.1 a ha) hp.2, ?_⟩
        intro p hp'; simp at hp'; rcases hp' with h | h
        · simp_all
        · exact hval p (List.mem_cons_of_mem _ h)
      · rename_i hlt hne
        have hne' : k ≠ k' := by simpa using hne
        have hgt : bytesLt k' k = true := by
          rcases bytesLt_total hne' with h | h
          · simp_all
          · exact h
        refine ⟨List.Pairwise.cons ?_ ihr.1, ?_⟩
        · intro a ha
          rcases mem_insert ha with h | h
          · subst h; exact hgt
          · exact hp.1 a h
        · intro p hp'; simp at hp'; rcases hp' with h | h
          · subst h; exact hval _ (by simp)
          · exact ihr.2 p h

/-- English: Erasing a key keeps a store well-formed. -/
theorem erase_wf {s : Store} (hs : s.WellFormed) (k : Bytes) : Store.WellFormed (s.erase k) :=
  ⟨hs.1.sublist (List.filter_sublist), fun p hp => hs.2 p (List.mem_filter.mp hp).1⟩

/-- English: Applying a valid write keeps a store well-formed. -/
theorem apply_wf {s : Store} (hs : s.WellFormed) {op : WriteOp Bytes} (hop : op.valid = true) :
    Store.WellFormed (op.apply s) := by
  cases op with
  | put k v =>
    simp [WriteOp.valid] at hop
    exact insert_wf hs hop.1 hop.2
  | delete k => exact erase_wf hs k

/-- English: Applying a list of valid writes in order keeps a store well-formed. -/
theorem foldl_apply_wf {ops : List (WriteOp Bytes)} (hops : ∀ op ∈ ops, op.valid = true) :
    ∀ {s : Store}, s.WellFormed → Store.WellFormed (ops.foldl WriteOp.apply s) := by
  induction ops with
  | nil => intro s hs; exact hs
  | cons op ops ih =>
    intro s hs
    exact ih (fun o ho => hops o (List.mem_cons_of_mem _ ho)) (apply_wf hs (hops op (by simp)))

/-- English: Every write in a valid batch is valid. -/
theorem validBatch_all {ops : List (WriteOp Bytes)} (h : validBatch ops = true) :
    ∀ op ∈ ops, op.valid = true := by
  simp [validBatch] at h; exact h.1.2

/-- English: Running a batch keeps a store well-formed. -/
theorem runBatch_wf {s : Store} (hs : s.WellFormed) (ops : List (WriteOp Bytes)) : Store.WellFormed (runBatch s ops).1 := by
  unfold runBatch; split
  · exact foldl_apply_wf (validBatch_all (by assumption)) hs
  · exact hs

/-- English: Every command takes a well-formed store to a well-formed store. -/
theorem step_wellFormed {s : Store} (hs : s.WellFormed) (c : Cmd Bytes) : Store.WellFormed (step s c).1 := by
  cases c <;> simp only [step] <;> (try split) <;> (try exact hs) <;> exact runBatch_wf hs _

/-- English: Running any commands from a well-formed store gives a well-formed store. -/
theorem runFrom_wf : ∀ (cmds : List (Cmd Bytes)) {s : Store}, s.WellFormed → Store.WellFormed (runFrom s cmds).1
  | [], _, hs => hs
  | c :: cs, s, hs => by
    simp only [runFrom]
    exact runFrom_wf cs (step_wellFormed hs c)

/-- English: A one-write batch is valid exactly when that write is valid. One write is always within the batch count and size limits. -/
theorem validBatch_single (op : WriteOp Bytes) : validBatch [op] = op.valid := by
  rw [Bool.eq_iff_iff]
  cases op <;>
  simp only [validBatch, WriteOp.valid, WriteOp.size, validKey, validValue, List.all_cons,
    List.all_nil, List.map_cons, List.map_nil, List.sum_cons, List.sum_nil, List.length_cons,
    List.length_nil, Bool.and_eq_true, Bool.and_true, decide_eq_true_eq] <;>
  simp only [maxKeyLen, maxValueLen, maxBatchOps, maxBatchBytes] <;> omega

/-- English: If a batch is valid, so is its first write on its own, and so are the remaining writes. -/
theorem validBatch_cons {op : WriteOp Bytes} {ops : List (WriteOp Bytes)}
    (h : validBatch (op :: ops) = true) : validBatch [op] = true ∧ validBatch ops = true := by
  have h' := h
  simp only [validBatch, Bool.and_eq_true, decide_eq_true_eq, List.all_cons, List.length_cons,
    List.map_cons, List.sum_cons] at h'
  obtain ⟨⟨hlen, hop, hall⟩, hsum⟩ := h'
  refine ⟨by rw [validBatch_single]; exact hop, ?_⟩
  simp only [validBatch, Bool.and_eq_true, decide_eq_true_eq]
  exact ⟨⟨by omega, hall⟩, by omega⟩

/-- English: `put k v` inserts the pair and answers ok when the key and value are valid. Otherwise it changes nothing and answers limitError. -/
theorem step_put (s : Store) (k v : Bytes) :
    step s (.put k v) = if (validKey k && validValue v) then (s.insert k v, .ok) else (s, .limitError) := by
  simp only [step, runBatch]; rw [validBatch_single]; rfl

/-- English: `delete k` erases the key and answers ok when the key is valid. Otherwise it changes nothing and answers limitError. -/
theorem step_delete (s : Store) (k : Bytes) :
    step s (.delete k) = if validKey k then (s.erase k, .ok) else (s, .limitError) := by
  simp only [step, runBatch]; rw [validBatch_single]; rfl

/-- English: A command that answers `limitError` changes nothing (R1, R7a, R8a). -/
theorem limitError_unchanged (s : Store) (c : Cmd Bytes) (h : (step s c).2 = .limitError) :
    (step s c).1 = s := by
  cases c with
  | get k => simp only [step]; split <;> rfl
  | put k v => rw [step_put] at h ⊢; split <;> simp_all
  | delete k => rw [step_delete] at h ⊢; split <;> simp_all
  | scan lo hi limit => simp only [step]; split <;> rfl
  | batch ops => simp only [step, runBatch] at h ⊢; split <;> simp_all

/-- English: `get`, `put` and `delete` with an invalid key answer `limitError` (R1). -/
theorem invalid_key_rejected (s : Store) (k v : Bytes) (h : validKey k = false) :
    (step s (.get k)).2 = .limitError ∧ (step s (.put k v)).2 = .limitError ∧
      (step s (.delete k)).2 = .limitError := by
  refine ⟨by simp [step, h], by simp [step_put, h], by simp [step_delete, h]⟩

/-- English: `put` with a value over 1 MiB answers `limitError` (R1). -/
theorem invalid_value_rejected (s : Store) (k v : Bytes) (h : validValue v = false) :
    (step s (.put k v)).2 = .limitError := by
  simp [step_put, h]

/-- English: `get` never changes anything (R4). -/
theorem get_unchanged (s : Store) (k : Bytes) : (step s (.get k)).1 = s := by
  simp only [step]; split <;> rfl

/-- English: With a valid key, `get k` answers with the looked-up value, or notFound. -/
theorem get_eq {s : Store} {k : Bytes} (hk : validKey k = true) :
    (step s (.get k)).2 = match s.lookup k with | some v => .value v | none => .notFound := by
  simp only [step, hk, ↓reduceIte]; rfl

/-- English: A valid `put k v` succeeds, and afterwards `get k` returns `v` (R5). -/
theorem put_then_get {s : Store} (_hs : s.WellFormed) {k v : Bytes}
    (hk : validKey k = true) (hv : validValue v = true) :
    (step s (.put k v)).2 = .ok ∧ (step (step s (.put k v)).1 (.get k)).2 = .value v := by
  simp [step_put, hk, hv, get_eq hk, lookup_insert_self]

/-- English: `put k v` leaves every other key unchanged (R5). -/
theorem put_other {s : Store} (_hs : s.WellFormed) {k k' v : Bytes} (hne : k' ≠ k) :
    (step s (.put k v)).1.lookup k' = s.lookup k' := by
  rw [step_put]; split
  · exact lookup_insert_ne s v hne
  · rfl

/-- English: A valid `delete k` succeeds, and afterwards `get k` is not found (R6). -/
theorem delete_then_get {s : Store} (_hs : s.WellFormed) {k : Bytes} (hk : validKey k = true) :
    (step s (.delete k)).2 = .ok ∧ (step (step s (.delete k)).1 (.get k)).2 = .notFound := by
  simp [step_delete, hk, get_eq hk, lookup_erase_self]

/-- English: `delete k` leaves every other key unchanged (R6). -/
theorem delete_other {s : Store} (_hs : s.WellFormed) {k k' : Bytes} (hne : k' ≠ k) :
    (step s (.delete k)).1.lookup k' = s.lookup k' := by
  rw [step_delete]; split
  · exact lookup_erase_ne s hne
  · rfl

/-- English: Deleting a missing key does nothing (R6). -/
theorem delete_missing {s : Store} {k : Bytes} (h : s.lookup k = none) :
    (step s (.delete k)).1 = s := by
  rw [step_delete]; split
  · exact erase_of_lookup_none h
  · rfl

/-- English: An invalid batch changes nothing and answers `limitError`. No write in it takes
effect (R8 atomicity, R8a). -/
theorem batch_invalid (s : Store) {ops : List (WriteOp Bytes)} (h : validBatch ops = false) :
    step s (.batch ops) = (s, .limitError) := by
  simp [step, runBatch, h]

/-- English: A valid batch has exactly the effect of running its writes one at a time, in
order, and each of those writes succeeds (R8). This is also the licence for group commit
(R18). -/
theorem batch_serial (s : Store) {ops : List (WriteOp Bytes)} (h : validBatch ops = true) :
    step s (.batch ops) = ((runFrom s (ops.map WriteOp.toCmd)).1, .ok) ∧
      (runFrom s (ops.map WriteOp.toCmd)).2 = ops.map (fun _ => (Response.ok : Response Bytes)) := by
  induction ops generalizing s with
  | nil => simp [step, runBatch, h, runFrom]
  | cons op ops ih =>
    obtain ⟨h1, h2⟩ := validBatch_cons h
    have hop : step s op.toCmd = (op.apply s, .ok) := by
      have : step s op.toCmd = runBatch s [op] := by cases op <;> rfl
      rw [this]; simp [runBatch, h1]
    obtain ⟨ih1, ih2⟩ := ih (s := op.apply s) h2
    have e1 : step s (.batch (op :: ops)) = ((op :: ops).foldl WriteOp.apply s, .ok) := by
      simp [step, runBatch, h]
    have e2 : step (op.apply s) (.batch ops) = (ops.foldl WriteOp.apply (op.apply s), .ok) := by
      simp [step, runBatch, h2]
    rw [e2] at ih1
    simp only [List.map_cons, runFrom, hop]
    refine ⟨?_, ?_⟩
    · rw [e1, List.foldl_cons]; exact ih1
    · simp [ih2]

/-! scan -/

/-- English: If looking up k gives v, the pair (k, v) is in the store. -/
theorem mem_of_lookup {s : Store} {k v : Bytes} (h : s.lookup k = some v) : (k, v) ∈ s := by
  induction s with
  | nil => simp [Store.lookup] at h
  | cons q rest ih =>
    rw [lookup_cons] at h
    split at h
    · rename_i hq; simp at h; subst hq; subst h; simp
    · exact List.mem_cons_of_mem _ (ih h)

/-- English: In a store with strictly ascending keys, looking up the key of any stored pair gives that pair's value. -/
theorem lookup_of_mem {s : Store} (hs : s.Pairwise (fun a b => bytesLt a.1 b.1 = true))
    {p : Bytes × Bytes} (hp : p ∈ s) : s.lookup p.1 = some p.2 := by
  induction s with
  | nil => simp at hp
  | cons q rest ih =>
    rw [List.pairwise_cons] at hs
    rw [lookup_cons]
    simp at hp
    rcases hp with rfl | hp
    · simp
    · have hlt := hs.1 p hp
      have hne : q.1 ≠ p.1 := fun e => by rw [e, bytesLt_irrefl] at hlt; simp at hlt
      simp [hne, ih hs.2 hp]

/-- English: A scan returns at most `limit` pairs (R7). -/
theorem scan_length_le (s : Store) (lo : Bytes) (hi : Upper Bytes) (limit : Nat) :
    (s.scan lo hi limit).length ≤ limit := List.length_take_le _ _

/-- English: On a well-formed store, a scan's result is in strictly ascending key order
(R7). -/
theorem scan_sorted {s : Store} (hs : s.WellFormed) (lo : Bytes) (hi : Upper Bytes) (limit : Nat) :
    (s.scan lo hi limit).Pairwise (fun a b => bytesLt a.1 b.1 = true) :=
  (hs.1.sublist List.filter_sublist).sublist (List.take_sublist _ _)

/-- English: Every pair a scan returns is in the store, with key ≥ `lo` and below `hi`
(R7). -/
theorem scan_sound {s : Store} (hs : s.WellFormed) (lo : Bytes) (hi : Upper Bytes) (limit : Nat)
    {p : Bytes × Bytes} (hp : p ∈ s.scan lo hi limit) :
    bytesLt p.1 lo = false ∧ hi.admits p.1 = true ∧ s.lookup p.1 = some p.2 := by
  have hf := List.mem_of_mem_take hp
  rw [List.mem_filter] at hf
  simp at hf
  exact ⟨hf.2.1, hf.2.2, lookup_of_mem hs.1 hf.1⟩

/-- English: A scan leaves out an in-range pair only when the limit was reached and that pair's
key is larger than every key returned. So the scan returns the *first* `limit` pairs in
range (R7). -/
theorem scan_complete {s : Store} (hs : s.WellFormed) (lo : Bytes) (hi : Upper Bytes)
    (limit : Nat) {k v : Bytes} (hkv : s.lookup k = some v) (hlo : bytesLt k lo = false)
    (hhi : hi.admits k = true) (hout : (k, v) ∉ s.scan lo hi limit) :
    (s.scan lo hi limit).length = limit ∧
      ∀ p ∈ s.scan lo hi limit, bytesLt p.1 k = true := by
  let F := s.filter (fun p => !bytesLt p.1 lo && hi.admits p.1)
  have hF : (k, v) ∈ F := List.mem_filter.mpr ⟨mem_of_lookup hkv, by simp [hlo, hhi]⟩
  have hFs : F.Pairwise (fun a b => bytesLt a.1 b.1 = true) := hs.1.sublist List.filter_sublist
  have hsplit : F = F.take limit ++ F.drop limit := (List.take_append_drop _ _).symm
  have hdrop : (k, v) ∈ F.drop limit := by
    rw [hsplit, List.mem_append] at hF
    rcases hF with h | h
    · exact absurd h hout
    · exact h
  refine ⟨?_, ?_⟩
  · have : limit < F.length := by
      have := List.length_pos_of_mem hdrop; simp at this; omega
    show (F.take limit).length = limit
    simp; omega
  · intro p hp
    have hpw := hFs
    rw [hsplit, List.pairwise_append] at hpw
    exact hpw.2.2 p hp (k, v) hdrop

/-- English: A scan with `limit = 0` returns nothing (R7a). -/
theorem scan_limit_zero (s : Store) (lo : Bytes) (hi : Upper Bytes) : s.scan lo hi 0 = [] := by
  simp [Store.scan]

/-- English: A scan with `lo ≥ hi` returns nothing (R7a). -/
theorem scan_empty_range (s : Store) {lo hi : Bytes} (h : bytesLt lo hi = false)
    (limit : Nat) : s.scan lo (.below hi) limit = [] := by
  simp only [Store.scan]
  rw [List.filter_eq_nil_iff.mpr]
  · simp
  · intro p _
    simp only [Upper.admits, Bool.and_eq_true, Bool.not_eq_true', not_and]
    intro hplo hphi
    by_cases he : p.1 = lo
    · rw [he] at hphi; simp_all
    · rcases bytesLt_total (Ne.symm he) with h1 | h1
      · have := bytesLt_trans h1 hphi; simp_all
      · simp_all

/-- English: A scan with valid bounds succeeds and changes nothing, even when the result is
empty (R7a). -/
theorem scan_ok (s : Store) {lo : Bytes} {hi : Upper Bytes} (limit : Nat)
    (hlo : validLower lo = true) (hhi : hi.valid = true) :
    step s (.scan lo hi limit) = (s, .pairs (s.scan lo hi limit)) := by
  simp [step, hlo, hhi]

/-- English: In a well-formed store each key appears at most once (R3). -/
theorem wellFormed_keys_nodup {s : Store} (hs : s.WellFormed) : (s.map Prod.fst).Nodup := by
  unfold List.Nodup
  rw [List.pairwise_map]
  exact hs.1.imp fun h e => by rw [e, bytesLt_irrefl] at h; simp at h

/-- English: Every state reachable from the empty store is well-formed. -/
theorem runFrom_empty_wellFormed (cmds : List (Cmd Bytes)) :
    (runFrom Store.empty cmds).1.WellFormed :=
  runFrom_wf cmds ⟨List.Pairwise.nil, fun _ h => by simp [Store.empty] at h⟩

end LeanKV.Spec
