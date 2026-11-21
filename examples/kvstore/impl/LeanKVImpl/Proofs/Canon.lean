import LeanKVImpl.Proofs.Recover

/-! Decoding is canonical: whatever decodes is exactly the encoding of what it decodes to
(Stage 4). So a log that recovers cleanly is `encodeLog` of its records. -/

set_option linter.deprecated false

namespace LeanKV.Proofs
open LeanKV.Spec

theorem unstuffN_canon : ∀ (n : Nat) (x : Bytes) {o : Bytes} {u : Nat},
    unstuffN n x = some (o, u) → x.take u = stuff o
  | 0, _, o, u, h => by simp [unstuffN] at h; obtain ⟨rfl, rfl⟩ := h; simp [stuff]
  | n + 1, [], _, _, h => by simp [unstuffN] at h
  | n + 1, a :: r, o, u, h => by
    by_cases ha : a = 0xC7
    · subst ha
      match r, h with
      | [], h => rw [unstuffN_C7_end] at h; simp at h
      | y :: r, h =>
        by_cases hy : y = 0x00
        · subst hy; rw [unstuffN_C7_00] at h
          cases hr : unstuffN n r with
          | none => rw [hr] at h; simp at h
          | some q =>
            rw [hr] at h; simp at h; obtain ⟨rfl, rfl⟩ := h
            have ih := unstuffN_canon n r hr
            simp [stuff, stuffByte, List.take_succ_cons]
            exact ih
        · rw [unstuffN_C7_bad n y hy] at h; simp at h
    · rw [unstuffN_plain n a ha] at h
      cases hr : unstuffN n r with
      | none => rw [hr] at h; simp at h
      | some q =>
        rw [hr] at h; simp at h; obtain ⟨rfl, rfl⟩ := h
        have ih := unstuffN_canon n r hr
        have : stuffByte a = [a] := by simp [stuffByte, ha]
        simp [stuff, this]
        exact ih

theorem u8_eq {a b : UInt8} (h : a.toNat = b.toNat) : a = b := UInt8.toNat_inj.mp h

theorem readU32le_canon {x : Bytes} {n : Nat} {r : Bytes} (h : readU32le x = some (n, r)) :
    x = u32le n ++ r ∧ n < 2 ^ 32 := by
  match x, h with
  | a :: b :: c :: d :: rest, h =>
    simp [readU32le] at h; obtain ⟨rfl, rfl⟩ := h
    have ha := a.toNat_lt; have hb := b.toNat_lt; have hc := c.toNat_lt; have hd := d.toNat_lt
    refine ⟨?_, by omega⟩
    simp only [u32le, List.cons_append, List.nil_append, List.cons.injEq, and_true]
    refine ⟨u8_eq ?_, u8_eq ?_, u8_eq ?_, u8_eq ?_⟩ <;> simp <;> omega

theorem takeExact_canon {n : Nat} {x k r : Bytes} (h : takeExact n x = some (k, r)) :
    x = k ++ r ∧ k.length = n := by
  unfold takeExact at h
  split at h
  · simp at h; obtain ⟨rfl, rfl⟩ := h; simp; omega
  · simp at h

theorem decodeOps_canon : ∀ (n : Nat) (x : Bytes) {ops : List (WriteOp Bytes)} {r : Bytes},
    decodeOps n x = some (ops, r) → x = ops.flatMap encodeOp ++ r ∧ ops.length = n
  | 0, x, ops, r, h => by simp [decodeOps] at h; obtain ⟨rfl, rfl⟩ := h; simp
  | n + 1, [], _, _, h => by simp [decodeOps] at h
  | n + 1, t :: x, ops, r, h => by
    by_cases t1 : t = 0x01
    · subst t1; rw [decodeOps_one] at h
      simp only [bind, Option.bind] at h
      cases h1 : readU32le x with
      | none => rw [h1] at h; simp at h
      | some p1 =>
        obtain ⟨klen, x1⟩ := p1; rw [h1] at h; simp only at h
        cases h2 : takeExact klen x1 with
        | none => rw [h2] at h; simp at h
        | some p2 =>
          obtain ⟨k, x2⟩ := p2; rw [h2] at h; simp only at h
          cases h3 : readU32le x2 with
          | none => rw [h3] at h; simp at h
          | some p3 =>
            obtain ⟨vlen, x3⟩ := p3; rw [h3] at h; simp only at h
            cases h4 : takeExact vlen x3 with
            | none => rw [h4] at h; simp at h
            | some p4 =>
              obtain ⟨v, x4⟩ := p4; rw [h4] at h; simp only at h
              cases h5 : decodeOps n x4 with
              | none => rw [h5] at h; simp at h
              | some p5 =>
                obtain ⟨ops', x5⟩ := p5; rw [h5] at h
                simp [pure] at h; obtain ⟨rfl, rfl⟩ := h
                obtain ⟨e1, -⟩ := readU32le_canon h1
                obtain ⟨e2, l2⟩ := takeExact_canon h2
                obtain ⟨e3, -⟩ := readU32le_canon h3
                obtain ⟨e4, l4⟩ := takeExact_canon h4
                obtain ⟨e5, l5⟩ := decodeOps_canon n x4 h5
                refine ⟨?_, by simp [l5]⟩
                subst e1 e2 e3 e4 e5
                simp [encodeOp, l2, l4]
    · by_cases t2 : t = 0x02
      · subst t2; rw [decodeOps_two] at h
        simp only [bind, Option.bind] at h
        cases h1 : readU32le x with
        | none => rw [h1] at h; simp at h
        | some p1 =>
          obtain ⟨klen, x1⟩ := p1; rw [h1] at h; simp only at h
          cases h2 : takeExact klen x1 with
          | none => rw [h2] at h; simp at h
          | some p2 =>
            obtain ⟨k, x2⟩ := p2; rw [h2] at h; simp only at h
            cases h5 : decodeOps n x2 with
            | none => rw [h5] at h; simp at h
            | some p5 =>
              obtain ⟨ops', x5⟩ := p5; rw [h5] at h
              simp [pure] at h; obtain ⟨rfl, rfl⟩ := h
              obtain ⟨e1, -⟩ := readU32le_canon h1
              obtain ⟨e2, l2⟩ := takeExact_canon h2
              obtain ⟨e5, l5⟩ := decodeOps_canon n x2 h5
              refine ⟨?_, by simp [l5]⟩
              subst e1 e2 e5
              simp [encodeOp, l2]
      · rw [decodeOps_other n t t1 t2] at h; simp at h

theorem decodePayload_canon {q : Bytes} {ops : List (WriteOp Bytes)}
    (h : decodePayload q = some ops) : q = encodePayload ops := by
  unfold decodePayload at h
  simp only [bind, Option.bind] at h
  cases h1 : readU32le q with
  | none => rw [h1] at h; simp at h
  | some p1 =>
  obtain ⟨n, q1⟩ := p1; rw [h1] at h; simp only at h
  cases h2 : decodeOps n q1 with
  | none => rw [h2] at h; simp at h
  | some p2 =>
  obtain ⟨ops', rest⟩ := p2; rw [h2] at h; simp only at h
  split at h
  · rename_i he
    simp [pure] at h; subst h
    obtain ⟨e1, -⟩ := readU32le_canon h1
    obtain ⟨e2, l2⟩ := decodeOps_canon n q1 h2
    have : rest = [] := by simpa using he
    subst this
    simp [e1, e2, encodePayload, l2]
  · simp at h

theorem decodeRecord_canon {b : Bytes} {ops : List (WriteOp Bytes)} {m : Nat}
    (h : decodeRecord b = some (ops, m)) : b.take m = encodeRecord ops ∧ validBatch ops = true := by
  unfold decodeRecord at h
  by_cases hm : magic.isPrefixOf b = true
  · obtain ⟨tl, hb⟩ := List.isPrefixOf_iff_prefix.mp hm
    simp only [hm, ↓reduceIte, bind, Option.bind] at h
    cases h1 : unstuffN 4 (b.drop magic.length) with
    | none => rw [h1] at h; simp at h
    | some p1 =>
    obtain ⟨lb, u1⟩ := p1; rw [h1] at h; simp only at h
    cases h2 : readU32le lb with
    | none => rw [h2] at h; simp at h
    | some p2 =>
    obtain ⟨len, r2⟩ := p2; rw [h2] at h; simp only at h
    cases h3 : unstuffN (len + 4) ((b.drop magic.length).drop u1) with
    | none => rw [h3] at h; simp at h
    | some p3 =>
    obtain ⟨more, u2⟩ := p3; rw [h3] at h; simp only at h
    split at h
    · rename_i hcrc
      cases h4 : decodePayload (more.take len) with
      | none => rw [h4] at h; simp at h
      | some ops' =>
      rw [h4] at h; simp only at h
      split at h
      · rename_i hv
        simp [pure] at h; obtain ⟨rfl, rfl⟩ := h
        refine ⟨?_, hv⟩
        have l1 := unstuffN_length _ _ h1
        have l3 := unstuffN_length _ _ h3
        obtain ⟨e2, -⟩ := readU32le_canon h2
        have r2nil : r2 = [] := by
          have := congrArg List.length e2
          rw [List.length_append, u32le_length, l1] at this
          exact List.eq_nil_of_length_eq_zero (by omega)
        subst r2nil; rw [List.append_nil] at e2
        have ep := decodePayload_canon h4
        have hc : more.drop len = u32le (crc32c (lb ++ more.take len)).toNat := by simpa using hcrc
        have hmore : more = more.take len ++ more.drop len := (List.take_append_drop _ _).symm
        have hlen : (more.take len).length = len := by simp [l3]
        have body : lb ++ more = recordBody ops' := by
          rw [hmore, hc, e2, recordBody, ← ep, hlen, List.append_assoc]
        have c1 := unstuffN_canon _ _ h1
        have c3 := unstuffN_canon _ _ h3
        subst hb
        rw [List.drop_left] at c1 c3
        rw [encodeRecord, ← body, stuff_append, ← c1, ← c3, ← List.take_add, Nat.add_assoc,
          List.take_append]
        simp only [Nat.add_sub_cancel_left]
        rw [List.take_of_length_le (by omega)]
      · simp at h
    · simp at h
  · simp only [hm] at h; simp at h

theorem readRecords_canon : ∀ (b : Bytes),
    b.take (readRecords b).2 = encodeLog (readRecords b).1 ∧
      (∀ ops ∈ (readRecords b).1, validBatch ops = true) ∧ (readRecords b).2 ≤ b.length := by
  intro b
  induction h : b.length using Nat.strongRecOn generalizing b with
  | _ len ih =>
    rw [readRecords]
    cases hd : decodeRecord b with
    | none => simp [encodeLog]
    | some r =>
      obtain ⟨ops, m⟩ := r
      simp only
      split
      · rename_i hc
        obtain ⟨c1, v1⟩ := decodeRecord_canon hd
        obtain ⟨i1, i2, i3⟩ := ih (b.drop m).length (by simp; omega) (b.drop m) rfl
        refine ⟨?_, ?_, ?_⟩
        · rw [List.take_add, c1, i1]; rfl
        · intro o ho; simp at ho; rcases ho with rfl | ho
          · exact v1
          · exact i2 o ho
        · simp at i3 ⊢; omega
      · simp [encodeLog]

/-- A log that recovers cleanly: its first `n` bytes are exactly the encoded recovered batches. -/
theorem recover_ok_canon {c : Bytes} {bs : List (List (WriteOp Bytes))} {n t : Nat}
    (h : recover c = .ok bs n t) :
    c.take n = encodeLog bs ∧ (∀ ops ∈ bs, validBatch ops = true) ∧ n ≤ c.length ∧
      t = c.length - n ∧ readRecords c = (bs, n) := by
  unfold recover at h
  have hr := readRecords_canon c
  generalize hrr : readRecords c = rr at h hr
  obtain ⟨rb, rn⟩ := rr
  simp only at h
  split at h
  · simp at h
  · simp at h; obtain ⟨rfl, rfl, rfl⟩ := h
    exact ⟨hr.1, hr.2.1, hr.2.2, rfl, rfl⟩

theorem recover_ok_noValidAfter {c : Bytes} {bs : List (List (WriteOp Bytes))} {n t : Nat}
    (h : recover c = .ok bs n t) : ∀ q, n < q → q < c.length → validRecordAt c q = false := by
  have hr := (recover_ok_canon h).2.2.2.2
  unfold recover at h
  rw [hr] at h; simp only at h
  split at h
  · simp at h
  · rename_i hany
    intro q h1 h2
    simp only [Bool.not_eq_true, List.any_eq_false, List.mem_range] at hany
    have := hany q h2; simp [h1] at this; simpa using this

theorem decodeRecord_some_len {b : Bytes} {o : List (WriteOp Bytes)} {m : Nat}
    (h : decodeRecord b = some (o, m)) : 0 < m ∧ m ≤ b.length := by
  obtain ⟨hle, -⟩ := decodeRecord_append h
  have c := (decodeRecord_canon h).1
  have := congrArg List.length c
  rw [List.length_take] at this
  have h4 := encodeRecord_length_pos o
  constructor <;> omega

/-- Every prefix of a cleanly recovering log, from its valid part up to the whole log, recovers
to the same records. -/
theorem recover_prefix {c : Bytes} {bs : List (List (WriteOp Bytes))} {n t : Nat}
    (h : recover c = .ok bs n t) {k : Nat} (hnk : n ≤ k) (hk : k ≤ c.length) :
    recover (c.take k) = .ok bs n (k - n) := by
  obtain ⟨hc, hv, hn, -, hrr⟩ := recover_ok_canon h
  have hnv := recover_ok_noValidAfter h
  have hlen : (encodeLog bs).length = n := by rw [← hc, List.length_take]; omega
  have hsplit : c = encodeLog bs ++ c.drop n := by rw [← hc, List.take_append_drop]
  -- decoding stopped at n because no record starts there
  have hd : decodeRecord (c.drop n) = none := by
    cases hdd : decodeRecord (c.drop n) with
    | none => rfl
    | some r =>
      obtain ⟨o, m⟩ := r
      have hm := decodeRecord_some_len hdd
      have := readRecords_encodeLog hv (c.drop n)
      rw [← hsplit, hrr] at this
      rw [readRecords, hdd] at this
      have hm2 : m ≤ c.length - n := by simpa using hm.2
      simp [hm.1, hm2] at this
  have hg : decodeRecord ((c.drop n).take (k - n)) = none := by
    cases hgg : decodeRecord ((c.drop n).take (k - n)) with
    | none => rfl
    | some r =>
      obtain ⟨-, he⟩ := decodeRecord_append hgg
      have := he ((c.drop n).drop (k - n))
      rw [List.take_append_drop, hd] at this; simp at this
  have htk : c.take k = encodeLog bs ++ (c.drop n).take (k - n) := by
    conv => lhs; rw [hsplit]
    rw [List.take_append, hlen, List.take_of_length_le (by omega)]
  have hrg : readRecords ((c.drop n).take (k - n)) = ([], 0) := by rw [readRecords, hg]
  have hrk : readRecords (c.take k) = (bs, n) := by
    rw [htk, readRecords_encodeLog hv, hrg]; simp [hlen]
  unfold recover
  rw [hrk]; simp only
  have hany : ((List.range (c.take k).length).any
      (fun q => decide (n < q) && validRecordAt (c.take k) q)) = false := by
    rw [List.any_eq_false]
    intro q hq hqt
    simp only [List.mem_range, List.length_take] at hq
    simp only [Bool.and_eq_true, decide_eq_true_eq] at hqt
    obtain ⟨hnq, hval⟩ := hqt
    unfold validRecordAt at hval
    cases hdq : decodeRecord ((c.take k).drop q) with
    | none => rw [hdq] at hval; simp at hval
    | some r =>
      obtain ⟨-, he⟩ := decodeRecord_append hdq
      have e2 := he (c.drop k)
      have hcq : (c.take k).drop q ++ c.drop k = c.drop q := by
        rw [List.drop_take]
        have : List.drop k c = List.drop (k - q) (List.drop q c) := by
          rw [List.drop_drop]; congr 1; omega
        rw [this, List.take_append_drop]
      rw [hcq] at e2
      have := hnv q hnq (by omega)
      unfold validRecordAt at this; rw [e2] at this; simp at this
  rw [hany]; simp; omega

end LeanKV.Proofs
