import LeanKVImpl.Proofs.Compare

/-! The AVL index's in-order contents follow the reference store (Stage 4). -/

set_option linter.deprecated false

namespace LeanKV.Proofs
open LeanKV.Spec LeanKV.Core

/-- Keys strictly ascending. -/
abbrev Sorted (s : Store) : Prop := s.Pairwise (fun a b => bytesLt a.1 b.1 = true)

theorem toList_mk (l : Tree) (k v : ByteArray) (r : Tree) :
    (mk l k v r).toList = l.toList ++ (toBytes k, toBytes v) :: r.toList := rfl

theorem toList_balance (l : Tree) (k v : ByteArray) (r : Tree) :
    (balance l k v r).toList = l.toList ++ (toBytes k, toBytes v) :: r.toList := by
  unfold balance
  split
  · split
    · split
      · simp [toList_mk, Tree.toList]
      · split <;> simp [toList_mk, Tree.toList]
    · rfl
  · split
    · split
      · split
        · simp [toList_mk, Tree.toList]
        · split <;> simp [toList_mk, Tree.toList]
      · rfl
    · rfl

/-! ### Reference-store lemmas on split lists -/

theorem lt_asymm {a b : Bytes} (h : bytesLt a b = true) : bytesLt b a = false := by
  cases h' : bytesLt b a
  · rfl
  · have := bytesLt_trans h h'; rw [bytesLt_irrefl] at this; simp at this

theorem lt_ne {a b : Bytes} (h : bytesLt a b = true) : a ≠ b := by
  intro e; subst e; rw [bytesLt_irrefl] at h; simp at h

theorem insert_left {A B : Store} {q : Bytes × Bytes} {k v : Bytes}
    (hA : ∀ a ∈ A, bytesLt a.1 q.1 = true) (hk : bytesLt k q.1 = true) :
    Store.insert (A ++ q :: B) k v = Store.insert A k v ++ q :: B := by
  induction A with
  | nil => simp [Store.insert, hk]
  | cons a A ih =>
    obtain ⟨ak, av⟩ := a
    simp only [List.cons_append, Store.insert]
    split
    · rfl
    · split
      · rfl
      · rw [ih (fun x hx => hA x (List.mem_cons_of_mem _ hx))]; rfl

theorem insert_right {A B : Store} {q : Bytes × Bytes} {k v : Bytes}
    (hA : ∀ a ∈ A, bytesLt a.1 q.1 = true) (hk : bytesLt q.1 k = true) :
    Store.insert (A ++ q :: B) k v = A ++ q :: Store.insert B k v := by
  induction A with
  | nil =>
    obtain ⟨qk, qv⟩ := q
    simp only [List.nil_append, Store.insert]
    rw [if_neg (by simp [lt_asymm hk]), if_neg (by simpa using (lt_ne hk).symm)]
  | cons a A ih =>
    obtain ⟨ak, av⟩ := a
    have hak := bytesLt_trans (hA (ak, av) (by simp)) hk
    simp only [List.cons_append, Store.insert]
    rw [if_neg (by simp [lt_asymm hak]), if_neg (by simpa using (lt_ne hak).symm),
      ih (fun x hx => hA x (List.mem_cons_of_mem _ hx))]

theorem insert_here {A B : Store} {q : Bytes × Bytes} {v : Bytes}
    (hA : ∀ a ∈ A, bytesLt a.1 q.1 = true) :
    Store.insert (A ++ q :: B) q.1 v = A ++ (q.1, v) :: B := by
  induction A with
  | nil => obtain ⟨qk, qv⟩ := q; simp [Store.insert, bytesLt_irrefl]
  | cons a A ih =>
    obtain ⟨ak, av⟩ := a
    have hak := hA (ak, av) (by simp)
    simp only [List.cons_append, Store.insert]
    rw [if_neg (by simp [lt_asymm hak]), if_neg (by simpa using (lt_ne hak).symm),
      ih (fun x hx => hA x (List.mem_cons_of_mem _ hx))]

theorem sorted_split {L R : Store} {q : Bytes × Bytes} (h : Sorted (L ++ q :: R)) :
    Sorted L ∧ Sorted R ∧ (∀ a ∈ L, bytesLt a.1 q.1 = true) ∧ (∀ b ∈ R, bytesLt q.1 b.1 = true) := by
  unfold Sorted at h
  rw [List.pairwise_append, List.pairwise_cons] at h
  exact ⟨h.1, h.2.1.2, fun a ha => h.2.2 a ha q (by simp), h.2.1.1⟩

/-! ### Tree operations -/

theorem toList_insert (t : Tree) (k v : ByteArray) (hs : Sorted t.toList) :
    (Core.insert t k v).toList = Store.insert t.toList (toBytes k) (toBytes v) := by
  induction t with
  | leaf => simp [Core.insert, toList_mk, Tree.toList, Store.insert]
  | node h l k' v' r ihl ihr =>
    simp only [Tree.toList] at hs ⊢
    obtain ⟨hl, hr, hlq, hrq⟩ := sorted_split hs
    unfold Core.insert
    rw [cmpBytes_spec]
    by_cases hlt : bytesLt (toBytes k) (toBytes k') = true
    · simp only [hlt, ↓reduceIte, toList_balance, ihl hl]
      rw [insert_left hlq hlt]
    · simp only [hlt, Bool.false_eq_true, ↓reduceIte]
      by_cases e : k = k'
      · subst e; simp only [↓reduceIte, Tree.toList]
        rw [insert_here (q := (toBytes k, toBytes v')) hlq]
      · simp only [e, ↓reduceIte, toList_balance, ihr hr]
        have hgt : bytesLt (toBytes k') (toBytes k) = true := by
          rcases bytesLt_total (fun h' => e (toBytes_inj h')) with h1 | h1
          · simp_all
          · exact h1
        rw [insert_right hlq hgt]

theorem removeMin_none {t : Tree} (h : removeMin t = none) : t = .leaf := by
  cases t with
  | leaf => rfl
  | node _ l _ _ _ => simp only [removeMin] at h; split at h <;> simp at h

theorem toList_removeMin : ∀ {t : Tree} {k v : ByteArray} {t' : Tree},
    removeMin t = some (k, v, t') → t.toList = (toBytes k, toBytes v) :: t'.toList
  | .leaf, _, _, _, h => by simp [removeMin] at h
  | .node _ l k0 v0 r, k, v, t', h => by
    simp only [removeMin] at h
    split at h
    · rename_i hl
      simp at h; obtain ⟨rfl, rfl, rfl⟩ := h
      rw [removeMin_none hl]; rfl
    · rename_i mk' mv l' hl
      simp at h; obtain ⟨rfl, rfl, rfl⟩ := h
      simp only [Tree.toList, toList_removeMin hl, toList_balance, List.cons_append]

theorem filter_keep {A : Store} {k : Bytes} (h : ∀ a ∈ A, a.1 ≠ k) :
    A.filter (fun p => p.1 != k) = A := by
  rw [List.filter_eq_self]; intro a ha; simpa using h a ha

theorem toList_erase (t : Tree) (k : ByteArray) (hs : Sorted t.toList) :
    (Core.erase t k).toList = Store.erase t.toList (toBytes k) := by
  induction t with
  | leaf => rfl
  | node h l k' v' r ihl ihr =>
    simp only [Tree.toList] at hs ⊢
    obtain ⟨hl, hr, hlq, hrq⟩ := sorted_split hs
    unfold Core.erase
    rw [cmpBytes_spec]
    simp only [Store.erase, List.filter_append, List.filter_cons]
    by_cases hlt : bytesLt (toBytes k) (toBytes k') = true
    · simp only [hlt, ↓reduceIte, toList_balance, ihl hl, Store.erase]
      have hne : toBytes k' ≠ toBytes k := (lt_ne hlt).symm
      rw [filter_keep (A := r.toList) (fun b hb => (lt_ne (bytesLt_trans hlt (hrq b hb))).symm)]
      simp [hne]
    · simp only [hlt, Bool.false_eq_true, ↓reduceIte]
      by_cases e : k = k'
      · subst e
        simp only [↓reduceIte]
        rw [filter_keep (A := l.toList) (fun a ha => lt_ne (hlq a ha)),
          filter_keep (A := r.toList) (fun b hb => (lt_ne (hrq b hb)).symm)]
        split
        · rename_i hm; rw [removeMin_none hm]; simp [Tree.toList]
        · rename_i mk' mv r' hm
          rw [toList_balance, ← toList_removeMin hm]; simp
      · have hgt : bytesLt (toBytes k') (toBytes k) = true := by
          rcases bytesLt_total (fun h' => e (toBytes_inj h')) with h1 | h1
          · simp_all
          · exact h1
        have hne : toBytes k' ≠ toBytes k := lt_ne hgt
        simp only [e, ↓reduceIte, toList_balance, ihr hr, Store.erase]
        rw [filter_keep (A := l.toList) (fun a ha => lt_ne (bytesLt_trans (hlq a ha) hgt))]
        simp [hne]

theorem lookup_append_none {A B : Store} {k : Bytes} (h : ∀ a ∈ A, a.1 ≠ k) :
    Store.lookup (A ++ B) k = Store.lookup B k := by
  induction A with
  | nil => rfl
  | cons a A ih =>
    rw [List.cons_append, lookup_cons, if_neg (h a (by simp))]
    exact ih (fun x hx => h x (List.mem_cons_of_mem _ hx))

theorem lookup_none_of {A : Store} {k : Bytes} (h : ∀ a ∈ A, a.1 ≠ k) : Store.lookup A k = none := by
  have := lookup_append_none (B := []) h; simpa [Store.lookup] using this

theorem lookup_append_left {A B : Store} {k : Bytes} (hB : ∀ b ∈ B, b.1 ≠ k) :
    Store.lookup (A ++ B) k = Store.lookup A k := by
  induction A with
  | nil => rw [List.nil_append, lookup_none_of hB]; rfl
  | cons a A ih =>
    rw [List.cons_append, lookup_cons, lookup_cons, ih]

theorem toList_lookup (t : Tree) (k : ByteArray) (hs : Sorted t.toList) :
    (Core.lookup t k).map toBytes = Store.lookup t.toList (toBytes k) := by
  induction t with
  | leaf => rfl
  | node h l k' v' r ihl ihr =>
    simp only [Tree.toList] at hs ⊢
    obtain ⟨hl, hr, hlq, hrq⟩ := sorted_split hs
    unfold Core.lookup
    rw [cmpBytes_spec]
    by_cases hlt : bytesLt (toBytes k) (toBytes k') = true
    · simp only [hlt, ↓reduceIte, ihl hl]
      rw [lookup_append_left]
      intro b hb; simp at hb
      rcases hb with rfl | hb
      · exact (lt_ne hlt).symm
      · exact (lt_ne (bytesLt_trans hlt (hrq b hb))).symm
    · simp only [hlt, Bool.false_eq_true, ↓reduceIte]
      by_cases e : k = k'
      · subst e; simp only [↓reduceIte, Option.map_some]
        rw [lookup_append_none (fun a ha => lt_ne (hlq a ha)), lookup_cons]; simp
      · have hgt : bytesLt (toBytes k') (toBytes k) = true := by
          rcases bytesLt_total (fun h' => e (toBytes_inj h')) with h1 | h1
          · simp_all
          · exact h1
        simp only [e, ↓reduceIte, ihr hr]
        rw [lookup_append_none (fun a ha => lt_ne (bytesLt_trans (hlq a ha) hgt)), lookup_cons]
        simp [lt_ne hgt]

end LeanKV.Proofs
