import LeanKVImpl.Proofs.Step

/-! The AVL invariant and the R17 height bound (Stage 4). -/

set_option linter.deprecated false

namespace LeanKV.Proofs
open LeanKV.Spec LeanKV.Core

/-- AVL invariant: cached heights are correct and siblings differ in height by at most one. -/
def Bal : Tree → Prop
  | .leaf => True
  | .node h l _ _ r => Bal l ∧ Bal r ∧ h = max l.height r.height + 1 ∧
      l.height ≤ r.height + 1 ∧ r.height ≤ l.height + 1

theorem ht_eq : ∀ {t : Tree}, Bal t → ht t = t.height
  | .leaf, _ => rfl
  | .node _ _ _ _ _, hb => by simp [ht, Tree.height, hb.2.2.1]

theorem height_mk (l : Tree) (k v : ByteArray) (r : Tree) (hl : Bal l) (hr : Bal r) :
    (mk l k v r).height = max l.height r.height + 1 := by
  simp [mk, Tree.height]

theorem bal_mk {l r : Tree} (hl : Bal l) (hr : Bal r) (h1 : l.height ≤ r.height + 1)
    (h2 : r.height ≤ l.height + 1) (k v : ByteArray) : Bal (mk l k v r) := by
  simp only [mk, Bal]; exact ⟨hl, hr, by rw [ht_eq hl, ht_eq hr], h1, h2⟩

theorem bal_balance {l r : Tree} (hl : Bal l) (hr : Bal r) (h1 : l.height ≤ r.height + 2)
    (h2 : r.height ≤ l.height + 2) (k v : ByteArray) :
    Bal (balance l k v r) ∧ max l.height r.height ≤ (balance l k v r).height ∧
      (balance l k v r).height ≤ max l.height r.height + 1 := by
  unfold balance
  rw [ht_eq hl, ht_eq hr]
  split
  · rename_i hlt
    match l, hl with
    | .node _ ll lk lv lr, hl =>
      obtain ⟨hll, hlr, hh, hb1, hb2⟩ := hl
      simp only [Tree.height] at hlt h1 h2 ⊢
      rw [ht_eq hll, ht_eq hlr]
      split
      · rename_i hle
        have i1 := bal_mk hlr hr (by omega) (by omega) k v
        refine ⟨bal_mk hll i1 (by simp [height_mk _ _ _ _ hlr hr]; omega)
          (by simp [height_mk _ _ _ _ hlr hr]; omega) lk lv, ?_, ?_⟩ <;>
          simp [height_mk, hll, hlr, hr, i1] <;> omega
      · rename_i hgt
        match lr, hlr with
        | .node _ lrl lrk lrv lrr, hlr =>
          obtain ⟨h3, h4, hh', hb3, hb4⟩ := hlr
          simp only [Tree.height] at *
          have i1 := bal_mk hll h3 (by omega) (by omega) lk lv
          have i2 := bal_mk h4 hr (by omega) (by omega) k v
          refine ⟨bal_mk i1 i2 (by simp [height_mk, hll, h3, h4, hr]; omega)
            (by simp [height_mk, hll, h3, h4, hr]; omega) lrk lrv, ?_, ?_⟩ <;>
            simp [height_mk, hll, h3, h4, hr, i1, i2] <;> omega
        | .leaf, _ => simp [Tree.height] at hgt
    | .leaf, _ => simp [Tree.height] at hlt
  · split
    · rename_i hnl hlt
      match r, hr with
      | .node _ rl rk rv rr, hr =>
        obtain ⟨hrl, hrr, hh, hb1, hb2⟩ := hr
        simp only [Tree.height] at hlt h1 h2 ⊢
        rw [ht_eq hrl, ht_eq hrr]
        split
        · rename_i hle
          have i1 := bal_mk hl hrl (by omega) (by omega) k v
          refine ⟨bal_mk i1 hrr (by simp [height_mk, hl, hrl]; omega)
            (by simp [height_mk, hl, hrl]; omega) rk rv, ?_, ?_⟩ <;>
            simp [height_mk, hl, hrl, hrr, i1] <;> omega
        · rename_i hgt
          match rl, hrl with
          | .node _ rll rlk rlv rlr, hrl =>
            obtain ⟨h3, h4, hh', hb3, hb4⟩ := hrl
            simp only [Tree.height] at *
            have i1 := bal_mk hl h3 (by omega) (by omega) k v
            have i2 := bal_mk h4 hrr (by omega) (by omega) rk rv
            refine ⟨bal_mk i1 i2 (by simp [height_mk, hl, h3, h4, hrr]; omega)
              (by simp [height_mk, hl, h3, h4, hrr]; omega) rlk rlv, ?_, ?_⟩ <;>
              simp [height_mk, hl, h3, h4, hrr, i1, i2] <;> omega
          | .leaf, _ => simp [Tree.height] at hgt
      | .leaf, _ => simp [Tree.height] at hlt
    · rename_i h3 h4
      refine ⟨bal_mk hl hr (by omega) (by omega) k v, ?_, ?_⟩ <;> simp [height_mk, hl, hr]

theorem balance_noRot {l r : Tree} (hl : Bal l) (hr : Bal r) (h1 : l.height ≤ r.height + 1)
    (h2 : r.height ≤ l.height + 1) (k v : ByteArray) : balance l k v r = mk l k v r := by
  unfold balance; rw [ht_eq hl, ht_eq hr, if_neg (by omega), if_neg (by omega)]

/-- Rebuilding a node after one child changed height by at most one (in either direction). -/
theorem bal_rebuild {l r : Tree} (hl : Bal l) (hr : Bal r) (h1 : l.height ≤ r.height + 2)
    (h2 : r.height ≤ l.height + 2) (k v : ByteArray) :
    Bal (balance l k v r) ∧
      ((l.height ≤ r.height + 1 ∧ r.height ≤ l.height + 1 ∧
          (balance l k v r).height = max l.height r.height + 1) ∨
        ((l.height = r.height + 2 ∨ r.height = l.height + 2) ∧
          max l.height r.height ≤ (balance l k v r).height ∧
          (balance l k v r).height ≤ max l.height r.height + 1)) := by
  obtain ⟨hb, lo, hi⟩ := bal_balance hl hr h1 h2 k v
  refine ⟨hb, ?_⟩
  by_cases hr' : l.height ≤ r.height + 1 ∧ r.height ≤ l.height + 1
  · left; refine ⟨hr'.1, hr'.2, ?_⟩
    rw [balance_noRot hl hr hr'.1 hr'.2]; simp [mk, Tree.height]
  · right; exact ⟨by omega, lo, hi⟩

theorem bal_insert : ∀ (t : Tree) (k v : ByteArray), Bal t →
    Bal (Core.insert t k v) ∧ t.height ≤ (Core.insert t k v).height ∧
      (Core.insert t k v).height ≤ t.height + 1
  | .leaf, k, v, _ => by
    refine ⟨bal_mk (l := .leaf) (r := .leaf) trivial trivial (by simp [Tree.height]) (by simp [Tree.height]) k v, ?_, ?_⟩ <;>
      simp [Core.insert, mk, Tree.height]
  | .node h l k' v' r, k, v, hb => by
    obtain ⟨hl, hr, hh, hb1, hb2⟩ := hb
    unfold Core.insert
    split
    · obtain ⟨hl', a1, a2⟩ := bal_insert l k v hl
      obtain ⟨hB, hc⟩ := bal_rebuild hl' hr (by omega) (by omega) k' v'
      refine ⟨hB, ?_, ?_⟩ <;> simp only [Tree.height] <;> omega
    · obtain ⟨hr', a1, a2⟩ := bal_insert r k v hr
      obtain ⟨hB, hc⟩ := bal_rebuild hl hr' (by omega) (by omega) k' v'
      refine ⟨hB, ?_, ?_⟩ <;> simp only [Tree.height] <;> omega
    · exact ⟨⟨hl, hr, hh, hb1, hb2⟩, by simp [Tree.height], by simp [Tree.height]⟩

theorem bal_removeMin : ∀ {t : Tree} {k v : ByteArray} {t' : Tree}, Bal t →
    removeMin t = some (k, v, t') → Bal t' ∧ t.height ≤ t'.height + 1 ∧ t'.height ≤ t.height
  | .leaf, _, _, _, _, h => by simp [removeMin] at h
  | .node hh l k0 v0 r, k, v, t', hb, h => by
    obtain ⟨hl, hr, he, hb1, hb2⟩ := hb
    simp only [removeMin] at h
    split at h
    · rename_i hn
      simp at h; obtain ⟨rfl, rfl, rfl⟩ := h
      have := removeMin_none hn; subst this
      simp only [Tree.height] at hb1 hb2 ⊢; exact ⟨hr, by omega, by omega⟩
    · rename_i mk' mv l' hm
      simp at h; obtain ⟨rfl, rfl, rfl⟩ := h
      obtain ⟨hl', a1, a2⟩ := bal_removeMin hl hm
      obtain ⟨hB, hc⟩ := bal_rebuild hl' hr (by omega) (by omega) k0 v0
      refine ⟨hB, ?_, ?_⟩ <;> simp only [Tree.height] <;> omega

theorem bal_erase : ∀ (t : Tree) (k : ByteArray), Bal t →
    Bal (Core.erase t k) ∧ t.height ≤ (Core.erase t k).height + 1 ∧ (Core.erase t k).height ≤ t.height
  | .leaf, _, _ => ⟨trivial, by simp [Core.erase, Tree.height], by simp [Core.erase, Tree.height]⟩
  | .node h l k' v r, k, hb => by
    obtain ⟨hl, hr, hh, hb1, hb2⟩ := hb
    unfold Core.erase
    split
    · obtain ⟨hl', a1, a2⟩ := bal_erase l k hl
      obtain ⟨hB, hc⟩ := bal_rebuild hl' hr (by omega) (by omega) k' v
      refine ⟨hB, ?_, ?_⟩ <;> simp only [Tree.height] <;> omega
    · obtain ⟨hr', a1, a2⟩ := bal_erase r k hr
      obtain ⟨hB, hc⟩ := bal_rebuild hl hr' (by omega) (by omega) k' v
      refine ⟨hB, ?_, ?_⟩ <;> simp only [Tree.height] <;> omega
    · split
      · rename_i hn
        have := removeMin_none hn; subst this
        simp only [Tree.height] at hb1 hb2 ⊢; exact ⟨hl, by omega, by omega⟩
      · rename_i mk' mv r' hm
        obtain ⟨hr', a1, a2⟩ := bal_removeMin hr hm
        obtain ⟨hB, hc⟩ := bal_rebuild hl hr' (by omega) (by omega) mk' mv
        refine ⟨hB, ?_, ?_⟩ <;> simp only [Tree.height] <;> omega

theorem size_node (h : Nat) (l : Tree) (k v : ByteArray) (r : Tree) :
    (Tree.node h l k v r).size = l.size + r.size + 1 := by
  simp [Tree.size, Tree.toList]; omega

theorem bal_size : ∀ {t : Tree}, Bal t → 2 ^ (t.height / 2) ≤ t.size + 1
  | .leaf, _ => by simp [Tree.height, Tree.size, Tree.toList]
  | .node h l k v r, hb => by
    obtain ⟨hl, hr, _, hb1, hb2⟩ := hb
    have il := bal_size hl
    have ir := bal_size hr
    rw [size_node]
    simp only [Tree.height]
    by_cases hsmall : max l.height r.height + 1 < 2
    · have : (max l.height r.height + 1) / 2 = 0 := by omega
      rw [this]; omega
    · have m := (max l.height r.height + 1 - 2) / 2
      have e : (max l.height r.height + 1) / 2 = (max l.height r.height + 1 - 2) / 2 + 1 := by omega
      have pl : 2 ^ ((max l.height r.height + 1 - 2) / 2) ≤ 2 ^ (l.height / 2) :=
        Nat.pow_le_pow_right (by decide) (by omega)
      have pr : 2 ^ ((max l.height r.height + 1 - 2) / 2) ≤ 2 ^ (r.height / 2) :=
        Nat.pow_le_pow_right (by decide) (by omega)
      rw [e, Nat.pow_succ]; omega

theorem bal_height_le {t : Tree} (hb : Bal t) : t.height ≤ 3 * Nat.log2 (t.size + 1) + 2 := by
  have h1 := bal_size hb
  have h2 : t.height / 2 ≤ Nat.log2 (t.size + 1) := (Nat.le_log2 (by omega)).mpr h1
  omega

theorem bal_applyOp {t : Tree} (hb : Bal t) (op : WriteOp ByteArray) : Bal (applyOp t op) := by
  cases op with
  | put k v => exact (bal_insert t k v hb).1
  | delete k => exact (bal_erase t k hb).1

theorem bal_foldl : ∀ (ops : List (WriteOp ByteArray)) {t : Tree}, Bal t → Bal (ops.foldl applyOp t)
  | [], _, hb => hb
  | op :: ops, _, hb => bal_foldl ops (bal_applyOp hb op)

theorem bal_step {t : Tree} (hb : Bal t) (c : Cmd ByteArray) : Bal (Core.step t c).1 := by
  cases c with
  | get k => simp only [Core.step]; split <;> exact hb
  | scan lo hi limit => cases hi <;> simp only [Core.step] <;> split <;> exact hb
  | put k v => simp only [Core.step, Core.runBatch]; split; exact bal_foldl _ hb; exact hb
  | delete k => simp only [Core.step, Core.runBatch]; split; exact bal_foldl _ hb; exact hb
  | batch ops => simp only [Core.step, Core.runBatch]; split; exact bal_foldl _ hb; exact hb

theorem bal_runCore : ∀ (cmds : List (Cmd ByteArray)) {t : Tree}, Bal t → Bal (runCore t cmds).1
  | [], _, hb => hb
  | c :: cs, t, hb => by simp only [runCore, runWith]; exact bal_runCore cs (bal_step hb c)

/-- `impl_height_le` for `Core.step`. -/
theorem core_height_le (cmds : List (Cmd ByteArray)) :
    (runCore .leaf cmds).1.height ≤ 3 * Nat.log2 ((runCore .leaf cmds).1.size + 1) + 2 :=
  bal_height_le (bal_runCore cmds trivial)

end LeanKV.Proofs
