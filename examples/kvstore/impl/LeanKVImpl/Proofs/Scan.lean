import LeanKVImpl.Proofs.Tree

/-! The pruning, early-stopping scan returns exactly the reference scan (Stage 4). -/

set_option linter.deprecated false

namespace LeanKV.Proofs
open LeanKV.Spec LeanKV.Core

/-- A pair of byte arrays as spec bytes. -/
def pb (p : ByteArray × ByteArray) : Bytes × Bytes := (toBytes p.1, toBytes p.2)

theorem admits_spec (hi : Upper ByteArray) (k : ByteArray) :
    admits hi k = (hi.map toBytes).admits (toBytes k) := by
  cases hi <;> simp [admits, Upper.admits, Upper.map, ltBytes_spec]

theorem not_admits_mono {hi : Upper Bytes} {k x : Bytes} (h : hi.admits k = false)
    (hk : bytesLt k x = true) : hi.admits x = false := by
  cases hi with
  | unbounded => simp [Upper.admits] at h
  | below b =>
    simp only [Upper.admits] at h ⊢
    cases hx : bytesLt x b
    · rfl
    · have := bytesLt_trans hk hx; rw [h] at this; simp at this

theorem scanAux_spec (lo : ByteArray) (hi : Upper ByteArray) (limit : Nat) (t : Tree)
    (hs : Sorted t.toList) (acc : Array (ByteArray × ByteArray)) :
    (scanAux lo hi limit t acc).toList.map pb =
      acc.toList.map pb ++ (t.toList.filter (fun p => !bytesLt p.1 (toBytes lo) &&
        (hi.map toBytes).admits p.1)).take (limit - acc.size) := by
  induction t generalizing acc with
  | leaf => simp [scanAux, Tree.toList]
  | node h l k v r ihl ihr =>
    simp only [Tree.toList] at hs ⊢
    obtain ⟨hl, hr, hlq, hrq⟩ := sorted_split hs
    simp only [scanAux]
    by_cases hlim : limit ≤ acc.size
    · simp [hlim, show limit - acc.size = 0 by omega]
    simp only [hlim, ↓reduceIte, ltBytes_spec, List.filter_append, List.filter_cons]
    by_cases hlo : bytesLt (toBytes k) (toBytes lo) = true
    · -- everything in l and k itself lies below lo
      simp only [hlo, ↓reduceIte, ihr hr, Bool.not_true, Bool.false_and, Bool.false_eq_true]
      rw [(List.filter_eq_nil_iff (l := l.toList)).mpr (fun a ha => by
        have := bytesLt_trans (hlq a ha) hlo; simp [this])]
      simp
    · simp only [hlo, Bool.false_eq_true, ↓reduceIte, Bool.not_false, Bool.true_and]
      have e1 := ihl hl acc
      have hsz : (scanAux lo hi limit l acc).size =
          acc.size + min (limit - acc.size) (l.toList.filter (fun p => !bytesLt p.1 (toBytes lo) &&
            (hi.map toBytes).admits p.1)).length := by
        have := congrArg List.length e1; simp at this; omega
      generalize hF : l.toList.filter (fun p => !bytesLt p.1 (toBytes lo) &&
        (hi.map toBytes).admits p.1) = FL at e1 hsz
      by_cases hlim1 : limit ≤ (scanAux lo hi limit l acc).size
      · simp only [hlim1, ↓reduceIte, e1, List.append_assoc]
        congr 1
        rw [List.take_append_of_le_length (by omega)]
      · simp only [hlim1, ↓reduceIte]
        have hFl : FL.length < limit - acc.size := by omega
        have hsz' : (scanAux lo hi limit l acc).size = acc.size + FL.length := by omega
        rw [← admits_spec]
        by_cases had : admits hi k = true
        · simp only [had, ↓reduceIte, Bool.and_true]
          rw [ihr hr, Array.toList_push, List.map_append, e1, Array.size_push, hsz', List.take_append,
            List.take_of_length_le (Nat.le_of_lt hFl)]
          have hn : limit - acc.size - FL.length = (limit - (acc.size + FL.length + 1)) + 1 := by omega
          rw [hn, List.take_succ_cons]
          simp [pb]
        · have had' : admits hi k = false := by simpa using had
          simp only [had', ↓reduceIte, Bool.and_false, Bool.false_eq_true]
          rw [(List.filter_eq_nil_iff (l := r.toList)).mpr (fun b hb => by
            have := not_admits_mono (by rw [← admits_spec]; exact had') (hrq b hb); simp [this])]
          rw [List.append_nil, e1, List.take_of_length_le (Nat.le_of_lt hFl)]

end LeanKV.Proofs
