import LeanKVImpl.Proofs.Scan

/-! `Core.step` follows the reference `step`, so the index answers exactly as the spec (Stage 4). -/

set_option linter.deprecated false

namespace LeanKV.Proofs
open LeanKV.Spec LeanKV.Core

theorem validKeyB_spec (k : ByteArray) : validKeyB k = validKey (toBytes k) := by
  simp [validKeyB, validKey, toBytes_length]

theorem validValueB_spec (v : ByteArray) : validValueB v = validValue (toBytes v) := by
  simp [validValueB, validValue, toBytes_length]

theorem opValid_spec (op : WriteOp ByteArray) : opValid op = (op.map toBytes).valid := by
  cases op <;> simp [opValid, WriteOp.valid, WriteOp.map, validKeyB_spec, validValueB_spec]

theorem opSize_spec (op : WriteOp ByteArray) : opSize op = (op.map toBytes).size := by
  cases op <;> simp [opSize, WriteOp.size, WriteOp.map, toBytes_length]

theorem batchValid_spec (ops : List (WriteOp ByteArray)) :
    batchValid ops = validBatch (ops.map (WriteOp.map toBytes)) := by
  have h1 : ops.all opValid = (ops.map (WriteOp.map toBytes)).all WriteOp.valid := by
    simp only [List.all_map, Function.comp_def]; congr 1; funext x; exact opValid_spec x
  have h2 : (ops.map opSize).sum = ((ops.map (WriteOp.map toBytes)).map WriteOp.size).sum := by
    simp only [List.map_map, Function.comp_def]; congr 2; funext x; exact opSize_spec x
  simp only [batchValid, validBatch, List.length_map, h1, h2]

theorem applyOp_spec {t : Tree} (hs : Sorted t.toList) (op : WriteOp ByteArray) :
    (applyOp t op).toList = WriteOp.apply t.toList (op.map toBytes) := by
  cases op <;> simp [applyOp, WriteOp.apply, WriteOp.map, toList_insert _ _ _ hs, toList_erase _ _ hs]

theorem foldl_applyOp_spec : ∀ (ops : List (WriteOp ByteArray)) {t : Tree},
    Store.WellFormed t.toList → (∀ op ∈ ops, opValid op = true) →
    (ops.foldl applyOp t).toList = (ops.map (WriteOp.map toBytes)).foldl WriteOp.apply t.toList
  | [], _, _, _ => rfl
  | op :: ops, t, hw, hv => by
    simp only [List.foldl_cons, List.map_cons]
    have h1 := applyOp_spec hw.1 op
    have hw' : Store.WellFormed (applyOp t op).toList := by
      rw [h1]; exact apply_wf hw (by rw [← opValid_spec]; exact hv op (by simp))
    rw [foldl_applyOp_spec ops hw' (fun o ho => hv o (List.mem_cons_of_mem _ ho)), h1]

theorem runBatch_spec {t : Tree} (hw : Store.WellFormed t.toList) (ops : List (WriteOp ByteArray)) :
    (Core.runBatch t ops).1.toList = (Spec.runBatch t.toList (ops.map (WriteOp.map toBytes))).1 ∧
    (Core.runBatch t ops).2.map toBytes = (Spec.runBatch t.toList (ops.map (WriteOp.map toBytes))).2 := by
  unfold Core.runBatch Spec.runBatch
  rw [← batchValid_spec]
  split
  · rename_i hb
    have hv : ∀ op ∈ ops, opValid op = true := by
      simp only [batchValid, Bool.and_eq_true, List.all_eq_true] at hb; exact hb.1.2
    exact ⟨foldl_applyOp_spec ops hw hv, rfl⟩
  · exact ⟨rfl, rfl⟩

theorem step_spec {t : Tree} (hw : Store.WellFormed t.toList) (c : Cmd ByteArray) :
    (Core.step t c).1.toList = (Spec.step t.toList (c.map toBytes)).1 ∧
    (Core.step t c).2.map toBytes = (Spec.step t.toList (c.map toBytes)).2 := by
  cases c with
  | get k =>
    simp only [Core.step, Spec.step, Cmd.map, validKeyB_spec]
    split
    · refine ⟨rfl, ?_⟩
      have := toList_lookup t k hw.1
      cases h : Core.lookup t k <;> rw [h] at this <;> simp at this <;> simp [← this, Response.map]
    · exact ⟨rfl, rfl⟩
  | put k v => exact runBatch_spec hw [.put k v]
  | delete k => exact runBatch_spec hw [.delete k]
  | batch ops => exact runBatch_spec hw ops
  | scan lo hi limit =>
    have e1 : Core.step t (.scan lo hi limit) =
        if (validLower (toBytes lo) && (hi.map toBytes).valid) = true
        then (t, .pairs (Core.scan t lo hi limit)) else (t, .limitError) := by
      cases hi <;> simp [Core.step, validLower, Upper.valid, Upper.map, validKeyB_spec, toBytes_length]
    rw [e1]
    simp only [Spec.step, Cmd.map]
    split
    · refine ⟨rfl, ?_⟩
      have := scanAux_spec lo hi limit t hw.1 #[]
      simp only [List.map_nil, List.nil_append, Array.size_empty, Nat.sub_zero] at this
      simp only [Response.map, Core.scan, Store.scan]
      congr 1
    · exact ⟨rfl, rfl⟩

/-- Run a step function over a list of commands. Type-generic on purpose: Lean reuses `match`
helpers of identical (monomorphic) shape, and a monomorphic copy of the spec's `Impl.runFrom`
here would make the generated solution's `Impl.runFrom` compile differently from the spec's. -/
def runWith {σ γ ρ : Type} (st : σ → γ → σ × ρ) (s : σ) : List γ → σ × List ρ
  | [] => (s, [])
  | c :: cs => ((runWith st (st s c).1 cs).1, (st s c).2 :: (runWith st (st s c).1 cs).2)

/-- Running commands with `Core.step`. -/
abbrev runCore (t : Tree) (cmds : List (Cmd ByteArray)) : Tree × List (Response ByteArray) :=
  runWith Core.step t cmds

/-- The spec's `runTree` is `runWith`; applied to the core step, it is `runCore`. -/
theorem runTree_eq (st : Tree → Cmd ByteArray → Tree × Response ByteArray) (t : Tree)
    (cmds : List (Cmd ByteArray)) : runTree st t cmds = runWith st t cmds := by
  induction cmds generalizing t with
  | nil => rfl
  | cons c cs ih => simp only [runTree, runWith, ih]

theorem runCore_spec : ∀ (cmds : List (Cmd ByteArray)) {t : Tree}, Store.WellFormed t.toList →
    (runCore t cmds).1.toList = (runFrom t.toList (cmds.map (Cmd.map toBytes))).1 ∧
    (runCore t cmds).2.map (Response.map toBytes) = (runFrom t.toList (cmds.map (Cmd.map toBytes))).2
  | [], _, _ => ⟨rfl, rfl⟩
  | c :: cs, t, hw => by
    obtain ⟨h1, h2⟩ := step_spec hw c
    have hw' : Store.WellFormed (Core.step t c).1.toList := by rw [h1]; exact step_wellFormed hw _
    obtain ⟨ih1, ih2⟩ := runCore_spec cs hw'
    rw [h1] at ih1 ih2
    simp only [runCore, runWith, runFrom, List.map_cons]
    exact ⟨ih1, by rw [← h2, ← ih2]⟩

/-- `impl_run_eq` and `impl_toList_eq` for `Core.step`, from the empty tree. -/
theorem core_run_eq (cmds : List (Cmd ByteArray)) :
    (runCore .leaf cmds).2.map (Response.map toBytes) = run (cmds.map (Cmd.map toBytes)) ∧
    (runCore .leaf cmds).1.toList = (runFrom Store.empty (cmds.map (Cmd.map toBytes))).1 := by
  have hw : Store.WellFormed Tree.leaf.toList := ⟨List.Pairwise.nil, fun _ h => by simp [Tree.toList] at h⟩
  obtain ⟨h1, h2⟩ := runCore_spec cmds hw
  exact ⟨h2, h1⟩

end LeanKV.Proofs
