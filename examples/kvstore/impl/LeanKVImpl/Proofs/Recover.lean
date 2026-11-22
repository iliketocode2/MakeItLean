import LeanKVImpl.Proofs.Step
import LeanKVImpl.Proofs.Crc
import LeanKVImpl.Proofs.Encode

/-! `impl_recover_eq`: the `ByteArray` decoder and recovery follow the spec step by step (Stage 4). -/

set_option linter.deprecated false

namespace LeanKV.Proofs
open LeanKV.Spec LeanKV.Core

/-! ### More `ByteArray` facts -/

theorem toBytes_push (a : ByteArray) (x : UInt8) : toBytes (a.push x) = toBytes a ++ [x] := by
  simp [toBytes_eq, ByteArray.data_push]

theorem toBytes_append (a b : ByteArray) : toBytes (a ++ b) = toBytes a ++ toBytes b := by
  simp [toBytes_eq, ByteArray.data_append]

theorem toBytes_empty : toBytes ByteArray.empty = [] := by
  simp [toBytes_eq]

theorem toBytes_extract (a : ByteArray) (s e : Nat) :
    toBytes (a.extract s e) = ((toBytes a).drop s).take (e - s) := by
  simp [toBytes_eq, ByteArray.data_extract, List.take_drop]

theorem getElem!_toBytes (b : ByteArray) (i : Nat) (h : i < b.size) : b[i]! = b[i] := by
  exact getElem!_pos b i h

/-! ### Unstuffing -/

theorem unstuffN_C7_00 (n : Nat) (r : Bytes) :
    unstuffN (n + 1) (0xC7 :: 0x00 :: r) = (unstuffN n r).map (fun p => (0xC7 :: p.1, p.2 + 2)) := by
  simp only [unstuffN, bind, Option.bind]; cases unstuffN n r <;> rfl

theorem unstuffN_C7_bad (n : Nat) (y : UInt8) (hy : y ≠ 0x00) (r : Bytes) :
    unstuffN (n + 1) (0xC7 :: y :: r) = none := by
  rw [unstuffN]; all_goals (intros; simp_all)

theorem unstuffN_C7_end (n : Nat) : unstuffN (n + 1) [0xC7] = none := by
  rw [unstuffN]; all_goals (intros; simp_all)

theorem unstuffN_plain (n : Nat) (x : UInt8) (hx : x ≠ 0xC7) (r : Bytes) :
    unstuffN (n + 1) (x :: r) = (unstuffN n r).map (fun p => (x :: p.1, p.2 + 1)) := by
  rw [unstuffN]
  · simp only [bind, Option.bind]; cases unstuffN n r <;> rfl
  all_goals (intros; simp_all)

theorem unstuffAt_spec (b : ByteArray) : ∀ (n i : Nat) (acc : ByteArray) (used : Nat),
    (unstuffAt b n i acc used).map (fun p => (toBytes p.1, p.2)) =
      (unstuffN n ((toBytes b).drop i)).map (fun p => (toBytes acc ++ p.1, used + p.2))
  | 0, i, acc, used => by simp [unstuffAt, unstuffN]
  | n + 1, i, acc, used => by
    unfold unstuffAt
    by_cases hi : i < b.size
    · rw [dif_pos hi, drop_toBytes_cons b i hi]
      by_cases hx : b[i] = 0xC7
      · rw [hx]; simp only [beq_self_eq_true, ↓reduceIte]
        by_cases hi1 : i + 1 < b.size
        · rw [dif_pos hi1, drop_toBytes_cons b (i + 1) hi1]
          by_cases hy : b[i + 1] = 0x00
          · rw [hy]; simp only [beq_self_eq_true, ↓reduceIte, unstuffN_C7_00, Option.map_map]
            rw [unstuffAt_spec b n (i + 2) (acc.push 0xC7) (used + 2), show i + 1 + 1 = i + 2 by omega]
            cases unstuffN n ((toBytes b).drop (i + 2)) <;> simp [toBytes_push]; omega
          · simp only [show (b[i + 1] == 0x00) = false by simpa using hy, Bool.false_eq_true,
              ↓reduceIte, unstuffN_C7_bad n _ hy]
            rfl
        · rw [dif_neg hi1, drop_toBytes_nil b (i + 1) hi1, unstuffN_C7_end]; rfl
      · simp only [show (b[i] == 0xC7) = false by simpa using hx, Bool.false_eq_true, ↓reduceIte,
          unstuffN_plain n _ hx, Option.map_map]
        rw [unstuffAt_spec b n (i + 1) (acc.push b[i]) (used + 1)]
        cases unstuffN n ((toBytes b).drop (i + 1)) <;> simp [toBytes_push]; omega
    · rw [dif_neg hi, drop_toBytes_nil b i hi]; rfl

/-! ### Numbers, writes, payloads -/

theorem readU32le_short {l : Bytes} (h : l.length < 4) : readU32le l = none := by
  match l, h with
  | [], _ => rfl
  | [_], _ => rfl
  | [_, _], _ => rfl
  | [_, _, _], _ => rfl

theorem readU32le_drop (b : ByteArray) (i : Nat) :
    readU32le ((toBytes b).drop i) = (readU32At b i).map (fun n => (n, (toBytes b).drop (i + 4))) := by
  unfold readU32At
  by_cases h : i + 4 ≤ b.size
  · rw [if_pos h, drop_toBytes_cons b i (by omega), drop_toBytes_cons b (i + 1) (by omega),
      drop_toBytes_cons b (i + 2) (by omega), drop_toBytes_cons b (i + 3) (by omega)]
    simp [readU32le, getElem!_toBytes b _ (by omega : i < b.size),
      getElem!_toBytes b _ (by omega : i + 1 < b.size), getElem!_toBytes b _ (by omega : i + 2 < b.size),
      getElem!_toBytes b _ (by omega : i + 3 < b.size), show i + 3 + 1 = i + 4 by omega]
  · rw [if_neg h, readU32le_short (by simp [toBytes_length]; omega)]; rfl

theorem takeExact_drop (p : ByteArray) (s n : Nat) (hs : s ≤ p.size) :
    takeExact n ((toBytes p).drop s) =
      if s + n ≤ p.size then some (toBytes (p.extract s (s + n)), (toBytes p).drop (s + n)) else none := by
  unfold takeExact
  simp only [List.length_drop, toBytes_length, toBytes_extract, List.drop_drop]
  by_cases h : s + n ≤ p.size
  · rw [if_pos (by omega), if_pos h]; simp [Nat.add_comm]
  · rw [if_neg (by omega), if_neg h]

theorem decodeOps_one (n : Nat) (r : Bytes) : decodeOps (n + 1) (0x01 :: r) = (do
    let (klen, b) ← readU32le r
    let (k, b) ← takeExact klen b
    let (vlen, b) ← readU32le b
    let (v, b) ← takeExact vlen b
    let (ops, b) ← decodeOps n b
    pure (.put k v :: ops, b)) := by rw [decodeOps]

theorem decodeOps_two (n : Nat) (r : Bytes) : decodeOps (n + 1) (0x02 :: r) = (do
    let (klen, b) ← readU32le r
    let (k, b) ← takeExact klen b
    let (ops, b) ← decodeOps n b
    pure (.delete k :: ops, b)) := by rw [decodeOps]

theorem decodeOps_other (n : Nat) (t : UInt8) (h1 : t ≠ 0x01) (h2 : t ≠ 0x02) (r : Bytes) :
    decodeOps (n + 1) (t :: r) = none := by
  rw [decodeOps]; all_goals (intros; simp_all)

/-- The result of `decodeOpsAt`, read as spec bytes. -/
def opsView (p : ByteArray) (r : List (WriteOp ByteArray) × Nat) : List (WriteOp Bytes) × Bytes :=
  (r.1.map (WriteOp.map toBytes), (toBytes p).drop r.2)

theorem decodeOpsAt_spec (p : ByteArray) : ∀ (n i : Nat), i ≤ p.size →
    (decodeOpsAt p n i).map (opsView p) = decodeOps n ((toBytes p).drop i) ∧
      ∀ r ∈ decodeOpsAt p n i, r.2 ≤ p.size
  | 0, i, hi => ⟨by simp [decodeOpsAt, decodeOps, opsView], by simp [decodeOpsAt]; omega⟩
  | n + 1, i, hi => by
    unfold decodeOpsAt
    by_cases hlt : i < p.size
    · rw [if_pos hlt, drop_toBytes_cons p i hlt, getElem!_toBytes p i hlt]
      by_cases t1 : p[i] = 0x01
      · rw [t1, decodeOps_one]
        simp only [beq_self_eq_true, ↓reduceIte, readU32le_drop p (i + 1)]
        cases hk : readU32At p (i + 1) with
        | none => simp [bind, Option.bind]
        | some kl =>
          have hk5 : i + 1 + 4 ≤ p.size := by
            unfold readU32At at hk; split at hk <;> simp_all
          simp only [bind, Option.bind, Option.map_some]
          rw [takeExact_drop p _ _ hk5, show i + 1 + 4 = i + 5 by omega]
          by_cases h1 : i + 5 + kl ≤ p.size
          · simp only [h1, ↓reduceIte, readU32le_drop p (i + 5 + kl)]
            cases hv : readU32At p (i + 5 + kl) with
            | none => simp
            | some vl =>
              have hv4 : i + 5 + kl + 4 ≤ p.size := by
                unfold readU32At at hv; split at hv <;> simp_all
              simp only [Option.map_some]
              rw [takeExact_drop p _ _ hv4]
              by_cases h2 : i + 5 + kl + 4 + vl ≤ p.size
              · simp only [h2, ↓reduceIte]
                obtain ⟨ih1, ih2⟩ := decodeOpsAt_spec p n (i + 5 + kl + 4 + vl) h2
                cases hr : decodeOpsAt p n (i + 5 + kl + 4 + vl) with
                | none => rw [hr] at ih1; simp at ih1; simp [← ih1]
                | some r =>
                  rw [hr] at ih1 ih2; simp [opsView] at ih1
                  simp [← ih1, opsView, WriteOp.map, pure]
                  exact ih2 r rfl
              · simp [h2]
          · simp [h1]
      · by_cases t2 : p[i] = 0x02
        · rw [t2, decodeOps_two]
          simp only [show ((0x02 : UInt8) == 0x01) = false by decide, Bool.false_eq_true, ↓reduceIte,
            beq_self_eq_true, readU32le_drop p (i + 1)]
          cases hk : readU32At p (i + 1) with
          | none => simp [bind, Option.bind]
          | some kl =>
            have hk5 : i + 1 + 4 ≤ p.size := by
              unfold readU32At at hk; split at hk <;> simp_all
            simp only [bind, Option.bind, Option.map_some]
            rw [takeExact_drop p _ _ hk5, show i + 1 + 4 = i + 5 by omega]
            by_cases h1 : i + 5 + kl ≤ p.size
            · simp only [h1, ↓reduceIte]
              obtain ⟨ih1, ih2⟩ := decodeOpsAt_spec p n (i + 5 + kl) h1
              cases hr : decodeOpsAt p n (i + 5 + kl) with
              | none => rw [hr] at ih1; simp at ih1; simp [← ih1]
              | some r =>
                rw [hr] at ih1 ih2; simp [opsView] at ih1
                simp [← ih1, opsView, WriteOp.map, pure]
                exact ih2 r rfl
            · simp [h1]
        · rw [decodeOps_other n _ t1 t2]
          simp [show (p[i] == 0x01) = false by simpa using t1, show (p[i] == 0x02) = false by simpa using t2]
    · rw [if_neg hlt, drop_toBytes_nil p i hlt]; exact ⟨rfl, by simp⟩

theorem decodePayloadBA_spec (p : ByteArray) :
    (decodePayloadBA p).map (List.map (WriteOp.map toBytes)) = decodePayload (toBytes p) := by
  unfold decodePayloadBA decodePayload
  have h0 := readU32le_drop p 0
  simp only [List.drop_zero, Nat.zero_add] at h0
  rw [h0]
  cases hn : readU32At p 0 with
  | none => rfl
  | some n =>
    have h4 : 4 ≤ p.size := by unfold readU32At at hn; split at hn <;> simp_all
    obtain ⟨e, hle⟩ := decodeOpsAt_spec p n 4 h4
    simp only [bind, Option.bind, Option.map_some]
    cases hr : decodeOpsAt p n 4 with
    | none => rw [hr] at e; simp at e; simp [← e]
    | some r =>
      rw [hr] at e; simp [opsView] at e
      have hj := hle r (by simp [hr])
      simp only [← e]
      by_cases hj' : r.2 = p.size
      · simp [hj', pure, List.drop_eq_nil_iff, toBytes_length]
      · have : ((toBytes p).drop r.2).isEmpty = false := by
          simp [List.drop_eq_nil_iff, toBytes_length]; omega
        simp [hj', this]

theorem unstuffN_length : ∀ (n : Nat) (x : Bytes) {o : Bytes} {u : Nat},
    unstuffN n x = some (o, u) → o.length = n
  | 0, _, o, u, h => by simp [unstuffN] at h; rw [h.1]; rfl
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
          | some q => rw [hr] at h; simp at h; rw [← h.1]; simp [unstuffN_length n r hr]
        · rw [unstuffN_C7_bad n y hy] at h; simp at h
    · rw [unstuffN_plain n a ha] at h
      cases hr : unstuffN n r with
      | none => rw [hr] at h; simp at h
      | some q => rw [hr] at h; simp at h; rw [← h.1]; simp [unstuffN_length n r hr]

theorem magicAt_spec (b : ByteArray) (pos : Nat) :
    magicAt b pos = magic.isPrefixOf ((toBytes b).drop pos) := by
  unfold magicAt
  by_cases h : pos + 4 ≤ b.size
  · rw [drop_toBytes_cons b pos (by omega), drop_toBytes_cons b (pos + 1) (by omega),
      drop_toBytes_cons b (pos + 2) (by omega), drop_toBytes_cons b (pos + 3) (by omega)]
    simp [magic, h, getElem!_toBytes b _ (by omega : pos < b.size),
      getElem!_toBytes b _ (by omega : pos + 1 < b.size), getElem!_toBytes b _ (by omega : pos + 2 < b.size),
      getElem!_toBytes b _ (by omega : pos + 3 < b.size), List.isPrefixOf]
    have e : ∀ x c : UInt8, (x == c) = (c == x) := fun x c => by
      by_cases h : x = c
      · subst h; rfl
      · rw [beq_eq_false_iff_ne.mpr h, beq_eq_false_iff_ne.mpr (Ne.symm h)]
    rw [e b[pos], e b[pos + 1], e b[pos + 2], e b[pos + 3]]; (try simp only [Bool.and_assoc])
  · have hl : ((toBytes b).drop pos).length < 4 := by rw [List.length_drop, toBytes_length]; omega
    have : magic.isPrefixOf ((toBytes b).drop pos) = false := by
      cases e : magic.isPrefixOf ((toBytes b).drop pos)
      · rfl
      · have := (List.isPrefixOf_iff_prefix.mp e).length_le
        simp only [magic, List.length_cons, List.length_nil, List.length_drop] at this hl; omega
    rw [this]; simp [h]

/-- The result of `decodeAt`, read as spec bytes. -/
def recView (r : List (WriteOp ByteArray) × Nat) : List (WriteOp Bytes) × Nat :=
  (r.1.map (WriteOp.map toBytes), r.2)

theorem decodeAt_spec (b : ByteArray) (pos : Nat) :
    (decodeAt b pos).map recView = decodeRecord ((toBytes b).drop pos) := by
  unfold decodeAt decodeRecord
  rw [← magicAt_spec]
  by_cases hm : magicAt b pos = true
  · simp only [hm, Bool.not_true, Bool.false_eq_true, ↓reduceIte, bind, Option.bind,
      show magic.length = 4 from rfl, List.drop_drop]
    have u1 := unstuffAt_spec b 4 (pos + 4) ByteArray.empty 0
    simp only [toBytes_empty, List.nil_append, Nat.zero_add] at u1
    cases h1 : unstuffAt b 4 (pos + 4) ByteArray.empty 0 <;>
      cases h1' : unstuffN 4 ((toBytes b).drop (pos + 4)) <;> simp only [h1, h1'] at u1
    · rfl
    · simp at u1
    · simp at u1
    rename_i r1 q1
    obtain ⟨lb, us1⟩ := r1
    simp at u1; obtain ⟨e1, e2⟩ := u1
    simp only [← e1, ← e2]
    have hr := readU32le_drop lb 0
    simp only [List.drop_zero, Nat.zero_add] at hr
    simp only [hr]
    cases hl : readU32At lb 0 with
    | none => rfl
    | some len =>
      simp only [Option.map_some]
      have u2 := unstuffAt_spec b (len + 4) (pos + 4 + us1) ByteArray.empty 0
      simp only [toBytes_empty, List.nil_append, Nat.zero_add] at u2
      cases h2 : unstuffAt b (len + 4) (pos + 4 + us1) ByteArray.empty 0 <;>
        cases h2' : unstuffN (len + 4) ((toBytes b).drop (pos + 4 + us1)) <;> simp only [h2, h2'] at u2
      · rfl
      · simp at u2
      · simp at u2
      rename_i r2 q2
      obtain ⟨more, us2⟩ := r2
      simp at u2; obtain ⟨f1, f2⟩ := u2
      have hlen := unstuffN_length _ _ h2'
      rw [← f1, toBytes_length] at hlen
      simp only [← f1, ← f2]
      have ep : toBytes (more.extract 0 len) = (toBytes more).take len := by
        rw [toBytes_extract]; simp
      have ec : (more.extract len (len + 4)).toList = (toBytes more).drop len := by
        show toBytes _ = _
        rw [toBytes_extract, Nat.add_sub_cancel_left, List.take_of_length_le]
        simp [toBytes_length]; omega
      simp only [crc32cBA_eq, toBytes_append, ep, ec]
      split
      · have dp := decodePayloadBA_spec (more.extract 0 len)
        rw [ep] at dp
        rw [← dp]
        cases hp : decodePayloadBA (more.extract 0 len) with
        | none => rfl
        | some ops =>
          simp only [Option.map_some, batchValid_spec]
          split <;> simp [pure, recView]
      · rfl
  · have : magic.isPrefixOf ((toBytes b).drop pos) = false := by
      rw [← magicAt_spec]; simpa using hm
    simp [hm]

/-! ### Reading records and recovery -/

theorem readFrom_spec (b : ByteArray) : ∀ (fuel pos : Nat) (acc : Array (List (WriteOp ByteArray))),
    pos ≤ b.size → b.size - pos < fuel →
    (readFrom b fuel pos acc).1.map (List.map (WriteOp.map toBytes)) =
        acc.toList.map (List.map (WriteOp.map toBytes)) ++ (readRecords ((toBytes b).drop pos)).1 ∧
      (readFrom b fuel pos acc).2 = pos + (readRecords ((toBytes b).drop pos)).2
  | 0, _, _, _, h => by omega
  | fuel + 1, pos, acc, hp, hf => by
    have hd := decodeAt_spec b pos
    unfold readFrom
    rw [readRecords]
    cases h1 : decodeAt b pos with
    | none => rw [h1] at hd; simp at hd; rw [← hd]; simp
    | some r =>
      obtain ⟨ops, n⟩ := r
      rw [h1] at hd; simp [recView] at hd; rw [← hd]
      simp only
      have hlen : ((toBytes b).drop pos).length = b.size - pos := by
        rw [List.length_drop, toBytes_length]
      by_cases hc : 0 < n ∧ pos + n ≤ b.size
      · have hc' : 0 < n ∧ n ≤ ((toBytes b).drop pos).length := by rw [hlen]; omega
        rw [if_pos hc, dif_pos hc']
        obtain ⟨ih1, ih2⟩ := readFrom_spec b fuel (pos + n) (acc.push ops) hc.2 (by omega)
        rw [List.drop_drop]
        refine ⟨?_, ?_⟩
        · rw [ih1]; simp [Nat.add_comm n pos]
        · rw [ih2]; simp [Nat.add_comm n pos]; omega
      · have hc' : ¬ (0 < n ∧ n ≤ ((toBytes b).drop pos).length) := by rw [hlen]; omega
        rw [if_neg hc, dif_neg hc']; simp

theorem magicAt_of_decodeAt {b : ByteArray} {q : Nat} (h : (decodeAt b q).isSome = true) :
    magicAt b q = true := by
  unfold decodeAt at h
  by_cases hm : magicAt b q = true
  · exact hm
  · simp [hm] at h

theorem validAfter_spec (b : ByteArray) (p : Nat) :
    validAfter b p = (List.range (toBytes b).length).any
      (fun q => decide (p < q) && validRecordAt (toBytes b) q) := by
  have hv : ∀ q, validRecordAt (toBytes b) q = (decodeAt b q).isSome := by
    intro q; unfold validRecordAt; rw [← decodeAt_spec]; cases decodeAt b q <;> rfl
  have hc : ∀ q, (b[q]! == 0xC7 && (decodeAt b q).isSome) = (decodeAt b q).isSome := by
    intro q
    cases h : (decodeAt b q).isSome
    · simp
    · have hm := magicAt_of_decodeAt h
      simp only [magicAt, Bool.and_eq_true] at hm
      simp [hm.1.1.1.2]
  unfold validAfter
  simp only [hc, hv, toBytes_length]
  rw [Bool.eq_iff_iff, List.any_eq_true, List.any_eq_true]
  constructor
  · rintro ⟨q, hq, h⟩
    rw [List.mem_range'_1] at hq
    exact ⟨q, List.mem_range.mpr (by omega), by simp [h]; omega⟩
  · rintro ⟨q, hq, h⟩
    rw [List.mem_range] at hq
    simp only [Bool.and_eq_true, decide_eq_true_eq] at h
    exact ⟨q, List.mem_range'_1.mpr ⟨by omega, by omega⟩, h.2⟩

/-- `impl_recover_eq` for the core recovery. -/
theorem core_recover_eq (b : ByteArray) : (Core.recover b).map toBytes = Spec.recover (toBytes b) := by
  obtain ⟨h1, h2⟩ := readFrom_spec b (b.size + 1) 0 #[] (by omega) (by omega)
  simp only [List.drop_zero, Nat.zero_add, Array.toList_empty, List.map_nil, List.nil_append] at h1 h2
  unfold Core.recover Spec.recover
  simp only
  rw [validAfter_spec, h2]
  split
  · rfl
  · simp only [Recovery.map, toBytes_length, h1]

end LeanKV.Proofs
