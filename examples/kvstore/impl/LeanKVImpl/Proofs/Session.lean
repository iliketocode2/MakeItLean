import LeanKVImpl.Proofs.FsOps
import LeanKVImpl.Proofs.Canon
import LeanKVImpl.Proofs.Balance

/-! The durable store's session theorems on the model file system (Stage 4). -/

set_option linter.deprecated false

namespace LeanKV.Proofs
open LeanKV.Spec

/-- Replaying recovered batches from the empty store (the spec's `Recovery.state?`). -/
def replay (bs : List (List (WriteOp Bytes))) : Store :=
  bs.foldl (fun s ops => ops.foldl WriteOp.apply s) Store.empty

theorem logState_ok {c : Bytes} {bs : List (List (WriteOp Bytes))} {n t : Nat}
    (h : recover c = .ok bs n t) : logState c = some (replay bs) := by
  simp [logState, h, Recovery.state?, replay]

/-- A disk holding exactly a clean log of valid batches, fully synced. -/
def Clean (d : Disk) (s : Store) : Prop :=
  ∃ bs : List (List (WriteOp Bytes)), (∀ ops ∈ bs, validBatch ops = true) ∧
    d = ⟨encodeLog bs, encodeLog bs⟩ ∧ replay bs = s

theorem commonPrefixLen_append (x y : Bytes) : x.length ≤ commonPrefixLen x (x ++ y) := by
  induction x with
  | nil => simp
  | cons a x ih => simp [commonPrefixLen]; omega

theorem commonPrefixLen_append' (x y : Bytes) : x.length ≤ commonPrefixLen (x ++ y) x := by
  induction x with
  | nil => simp
  | cons a x ih => simp [commonPrefixLen]; omega

theorem commonPrefixLen_take (x : Bytes) (n : Nat) :
    (x.take n).length ≤ commonPrefixLen x (x.take n) := by
  have := commonPrefixLen_append' (x.take n) (x.drop n)
  rw [List.take_append_drop] at this; exact this

/-- A crash leaves a prefix of the durable or the current version, at least as long as their
common prefix. -/
theorem crash_cases (d : Disk) (ch : CrashChoice) :
    ∃ K, commonPrefixLen d.durable d.content ≤ K ∧
      (crashOutcome d ch = d.durable.take K ∨ crashOutcome d ch = d.content.take K) := by
  refine ⟨max (commonPrefixLen d.durable d.content) ch.len, by omega, ?_⟩
  unfold crashOutcome
  cases ch.keepDurable <;> simp

theorem clean_crash {d : Disk} {s : Store} (hc : Clean d s) (ch : CrashChoice) :
    logState (crashOutcome d ch) = some s := by
  obtain ⟨bs, hv, rfl, rfl⟩ := hc
  obtain ⟨K, hK, hx⟩ := crash_cases ⟨encodeLog bs, encodeLog bs⟩ ch
  have hl := commonPrefixLen_append' (encodeLog bs) []
  simp only [List.append_nil] at hl
  have : crashOutcome ⟨encodeLog bs, encodeLog bs⟩ ch = encodeLog bs := by
    rcases hx with h | h <;> rw [h] <;> exact List.take_of_length_le (by simp at hK ⊢; omega)
  rw [this]; exact logState_ok (recover_encodeLog hv)

/-- A write in flight: the log `encodeLog bs` is durable and the current version has some prefix
`y` of the next record appended. Every crash recovers `bs`, or `bs` plus the new batch. -/
theorem inflight_crash {bs : List (List (WriteOp Bytes))} (hv : ∀ ops ∈ bs, validBatch ops = true)
    {ops : List (WriteOp Bytes)} (hops : validBatch ops = true) {y : Bytes}
    (hy : y.IsPrefix (encodeRecord ops)) (ch : CrashChoice) :
    logState (crashOutcome ⟨encodeLog bs ++ y, encodeLog bs⟩ ch) = some (replay bs) ∨
      logState (crashOutcome ⟨encodeLog bs ++ y, encodeLog bs⟩ ch) = some (replay (bs ++ [ops])) := by
  obtain ⟨K, hK, hx⟩ := crash_cases ⟨encodeLog bs ++ y, encodeLog bs⟩ ch
  have hl := commonPrefixLen_append (encodeLog bs) y
  simp only at hK hx
  rcases hx with h | h
  · rw [h, List.take_of_length_le (by omega)]
    left; exact logState_ok (recover_encodeLog hv)
  · rw [h, List.take_append, List.take_of_length_le (by omega)]
    have hp : (y.take (K - (encodeLog bs).length)).IsPrefix (encodeRecord ops) :=
      (List.take_prefix _ _).trans hy
    by_cases hlt : (y.take (K - (encodeLog bs).length)).length < (encodeRecord ops).length
    · left; exact logState_ok (recover_torn_tail hv hops hp hlt)
    · right
      have heq : y.take (K - (encodeLog bs).length) = encodeRecord ops :=
        hp.eq_of_length (by have := hp.length_le; omega)
      rw [heq, recover_after_truncate hv hops |> logState_ok]

/-- Every prefix of a recovering log that keeps its valid part recovers to the same state. -/
theorem logState_take {c0 : Bytes} {bs : List (List (WriteOp Bytes))} {n t : Nat}
    (h : recover c0 = .ok bs n t) {K : Nat} (hK : n ≤ K) : logState (c0.take K) = some (replay bs) := by
  have hn := (recover_ok_canon h).2.2.1
  by_cases hk : K ≤ c0.length
  · exact logState_ok (recover_prefix h hK hk)
  · rw [List.take_of_length_le (by omega)]; exact logState_ok h

theorem core_recover_ok {c0 : Bytes} {bs : List (List (WriteOp Bytes))} {n t : Nat}
    (h : recover c0 = .ok bs n t) :
    ∃ bs', Core.recover (ofBytes c0) = .ok bs' n t ∧ bs'.map (List.map (WriteOp.map toBytes)) = bs := by
  have e := core_recover_eq (ofBytes c0)
  rw [toBytes_ofBytes, h] at e
  cases hr : Core.recover (ofBytes c0) with
  | corrupt p => rw [hr] at e; simp [Recovery.map] at e
  | ok bs' n' t' =>
    rw [hr] at e; simp [Recovery.map] at e
    obtain ⟨e1, rfl, rfl⟩ := e
    exact ⟨bs', rfl, e1⟩

/-- Building the index by replaying recovered batches gives the replayed reference store, keeps
the AVL invariant and keeps the store well-formed. -/
theorem build_index : ∀ (bs' : List (List (WriteOp ByteArray))) {t : Tree},
    Store.WellFormed t.toList → Bal t →
    (∀ ops ∈ bs', validBatch (ops.map (WriteOp.map toBytes)) = true) →
    (bs'.foldl (fun t ops => ops.foldl Core.applyOp t) t).toList =
      (bs'.map (List.map (WriteOp.map toBytes))).foldl (fun s ops => ops.foldl WriteOp.apply s) t.toList ∧
    Store.WellFormed (bs'.foldl (fun t ops => ops.foldl Core.applyOp t) t).toList ∧
    Bal (bs'.foldl (fun t ops => ops.foldl Core.applyOp t) t)
  | [], _, hw, hb, _ => ⟨rfl, hw, hb⟩
  | ops :: bs', t, hw, hb, hv => by
    have hvo : ∀ op ∈ ops, Core.opValid op = true := by
      have := hv ops (by simp); rw [← batchValid_spec] at this
      simp only [Core.batchValid, Bool.and_eq_true, List.all_eq_true] at this; exact this.1.2
    have e := foldl_applyOp_spec ops hw hvo
    have hw' : Store.WellFormed (ops.foldl Core.applyOp t).toList := by
      rw [e]; exact foldl_apply_wf (validBatch_all (hv ops (by simp))) hw
    obtain ⟨i1, i2, i3⟩ := build_index bs' hw' (bal_foldl ops hb) (fun o ho => hv o (List.mem_cons_of_mem _ ho))
    simp only [List.foldl_cons, List.map_cons]
    rw [← e]; exact ⟨i1, i2, i3⟩

/-- What opening a healthy log on the model file system can do. -/
def OpenOk (s0 : Store) (out : Except (Reply ByteArray) Handle × FsState) : Prop :=
  match out.1 with
  | .error r => r.isIOError = true ∧ ∀ ch, logState (crashOutcome out.2.disk ch) = some s0
  | .ok h => Clean out.2.disk s0 ∧ h.failed = false ∧ h.index.toList = s0 ∧ Bal h.index ∧
      Store.WellFormed s0

theorem open_spec {c0 : Bytes} {s0 : Store} (hs0 : logState c0 = some s0) (φ : List Fault) :
    OpenOk s0 ((Core.openStore : FsM _).run ⟨⟨c0, c0⟩, φ⟩) ∧
      (φ = [] → ∃ h, ((Core.openStore : FsM _).run ⟨⟨c0, c0⟩, φ⟩).1 = .ok h ∧
        ((Core.openStore : FsM _).run ⟨⟨c0, c0⟩, φ⟩).2.faults = []) := by
  cases hr : recover c0 with
  | corrupt p => simp [logState, hr, Recovery.state?] at hs0
  | ok bs n t =>
  have hs : replay bs = s0 := by
    have := logState_ok hr; rw [hs0] at this; exact (Option.some.inj this).symm
  obtain ⟨hc, hv, hn, ht, -⟩ := recover_ok_canon hr
  obtain ⟨bs', hcr, hbs⟩ := core_recover_ok hr
  have hv' : ∀ ops ∈ bs', validBatch (ops.map (WriteOp.map toBytes)) = true := by
    intro ops ho; apply hv; rw [← hbs]; exact List.mem_map_of_mem ho
  obtain ⟨i1, i2, i3⟩ := build_index bs' (t := .leaf)
    ⟨List.Pairwise.nil, fun _ h => by simp [Tree.toList] at h⟩ trivial hv'
  simp only [Tree.toList] at i1 i2
  rw [hbs] at i1
  have hidx : (bs'.foldl (fun t ops => ops.foldl Core.applyOp t) Tree.leaf).toList = s0 := by
    rw [i1, ← hs]; rfl
  have hwf : Store.WellFormed s0 := by rw [← hidx]; exact i2
  unfold Core.openStore
  rw [bind_run, readAll_run]
  cases hf : (nextFault φ).1 with
  | fail k =>
    dsimp only; try simp only [↓reduceIte, ite_true, Bool.false_eq_true, pure_run]
    refine ⟨⟨rfl, fun ch => ?_⟩, fun h0 => by subst h0; simp [nextFault] at hf⟩
    obtain ⟨K, hK, hx⟩ := crash_cases ⟨c0, c0⟩ ch
    have := commonPrefixLen_append' c0 []; simp only [List.append_nil] at this
    rcases hx with h | h <;> rw [h, List.take_of_length_le (by simp at hK ⊢; omega)] <;> exact hs0
  | ok =>
    dsimp only; simp only [toBytes_ofBytes, hcr]
    by_cases htp : t > 0
    · simp only [htp, ↓reduceIte, bind_run, truncate_run]
      cases hf2 : (nextFault (nextFault φ).2).1 with
      | fail k =>
        dsimp only; try simp only [↓reduceIte, ite_true, Bool.false_eq_true, pure_run]
        refine ⟨⟨rfl, fun ch => ?_⟩, fun h0 => by subst h0; simp [nextFault] at hf2⟩
        obtain ⟨K, hK, hx⟩ := crash_cases ⟨c0, c0⟩ ch
        have := commonPrefixLen_append' c0 []; simp only [List.append_nil] at this
        rcases hx with h | h <;> rw [h, List.take_of_length_le (by simp at hK ⊢; omega)] <;> exact hs0
      | ok =>
        simp only [↓reduceIte, bind_run, sync_run]
        cases hf3 : (nextFault (nextFault (nextFault φ).2).2).1 with
        | fail k =>
          dsimp only; try simp only [↓reduceIte, ite_true, Bool.false_eq_true, pure_run]
          refine ⟨⟨rfl, fun ch => ?_⟩, fun h0 => by subst h0; simp [nextFault] at hf3⟩
          obtain ⟨K, hK, hx⟩ := crash_cases ⟨c0.take n, c0⟩ ch
          have hl := commonPrefixLen_take c0 n
          simp only [List.length_take] at hl hK hx
          rw [← hs]
          rcases hx with h | h
          · rw [h]; exact logState_take hr (by omega)
          · rw [h, List.take_take]; exact logState_take hr (by omega)
        | ok =>
          dsimp only; try simp only [↓reduceIte, ite_true, Bool.false_eq_true, pure_run]
          refine ⟨⟨⟨bs, hv, by rw [hc], hs⟩, rfl, hidx, i3, hwf⟩, fun h0 => ⟨_, rfl, ?_⟩⟩
          subst h0; rfl
    · simp only [htp, ↓reduceIte]
      have hn' : n = c0.length := by omega
      have hce : c0 = encodeLog bs := by rw [← hc, hn', List.take_length]
      refine ⟨⟨⟨bs, hv, by rw [← hce]; rfl, hs⟩, rfl, hidx, i3, hwf⟩, fun h0 => ⟨_, rfl, ?_⟩⟩
      subst h0; rfl

/-! ### One command -/

/-- An open, healthy store whose synced log and index both stand for reference state `s`. -/
def Good (h : Handle) (st : FsState) (s : Store) : Prop :=
  h.failed = false ∧ Clean st.disk s ∧ h.index.toList = s ∧ Bal h.index ∧ Store.WellFormed s

theorem ofResponse_matches {d : ByteArray} (r : Response ByteArray) :
    ((Reply.ofResponse d r).map toBytes).matches (r.map toBytes) = true := by
  cases r <;> simp [Reply.ofResponse, Reply.map, Response.map, Reply.matches]

theorem writes_step {s : Store} {x : Cmd ByteArray} {ops : List (WriteOp ByteArray)}
    (hw : Core.writesOf x = some ops) :
    Spec.step s (x.map toBytes) = Spec.runBatch s (ops.map (WriteOp.map toBytes)) := by
  cases x <;> simp [Core.writesOf] at hw <;> subst hw <;> rfl

theorem runBatch_ok {s : Store} {ops : List (WriteOp Bytes)} (h : (Spec.runBatch s ops).2 = .ok) :
    validBatch ops = true ∧ (Spec.runBatch s ops).1 = ops.foldl WriteOp.apply s := by
  unfold Spec.runBatch at h ⊢; split at h <;> simp_all

theorem nowrite_state {s : Store} {x : Cmd ByteArray}
    (h : ∀ ops, Core.writesOf x = some ops → (Spec.step s (x.map toBytes)).2 ≠ .ok) :
    (Spec.step s (x.map toBytes)).1 = s := by
  cases hw : Core.writesOf x with
  | some ops =>
    have hne := h ops hw
    rw [writes_step hw] at hne ⊢
    unfold Spec.runBatch at hne ⊢; split <;> simp_all
  | none =>
    cases x <;> simp [Core.writesOf] at hw
    · exact get_unchanged s _
    · simp only [Cmd.map, Spec.step]; split <;> rfl

theorem replay_append (bs : List (List (WriteOp Bytes))) (ops : List (WriteOp Bytes)) :
    replay (bs ++ [ops]) = ops.foldl WriteOp.apply (replay bs) := by
  simp [replay, List.foldl_append]

/-- What one command does to a healthy store: either it succeeds and the store stays healthy at
the next reference state, or it hits an I/O error, blocks itself, and every crash recovers the
state before or after the command. -/
theorem exec_spec {h : Handle} {st : FsState} {s : Store} (hg : Good h st s) (x : Cmd ByteArray) :
    let out := (Core.exec h x : FsM _).run st
    let sp := Spec.step s (x.map toBytes)
    ((Good out.1.1 out.2 sp.1 ∧ ((out.1.2.map toBytes).matches sp.2 = true) ∧
        (st.faults = [] → out.2.faults = [])) ∨
      (st.faults ≠ [] ∧ out.1.2.isIOError = true ∧ out.1.1.failed = true ∧
        ∀ ch, logState (crashOutcome out.2.disk ch) = some s ∨
          logState (crashOutcome out.2.disk ch) = some sp.1)) := by
  obtain ⟨hf, ⟨bs, hv, hd, hrs⟩, hix, hb, hw⟩ := hg
  obtain ⟨d, fs⟩ := st
  simp only at hd; subst hd
  obtain ⟨e1, e2⟩ := step_spec (t := h.index) (by rw [hix]; exact hw) x
  rw [hix] at e1 e2
  have hb' := bal_step hb x
  unfold Core.exec
  simp only [hf, Bool.false_eq_true, ↓reduceIte]
  generalize hst : Core.step h.index x = res at e1 e2 hb'
  obtain ⟨t', resp⟩ := res
  simp only at e1 e2 hb' ⊢
  cases hwr : Core.writesOf x with
  | none =>
    have hs' := nowrite_state (s := s) (x := x) (fun ops h => by rw [hwr] at h; cases h)
    simp only [pure_run]
    left
    refine ⟨⟨rfl, ⟨bs, hv, rfl, by rw [hrs, hs']⟩, by simp [e1], hb', by rw [hs']; exact hw⟩,
      by rw [← e2]; exact ofResponse_matches resp, fun h0 => h0⟩
  | some ops =>
    cases resp with
    | ok =>
      have hsb := writes_step (s := s) hwr
      have hok : (Spec.runBatch s (ops.map (WriteOp.map toBytes))).2 = .ok := by
        rw [← hsb, ← e2]; rfl
      obtain ⟨hvb, hfold⟩ := runBatch_ok hok
      have hs' : (Spec.step s (x.map toBytes)).1 = replay (bs ++ [ops.map (WriteOp.map toBytes)]) := by
        rw [hsb, hfold, replay_append, hrs]
      have hrec := core_encodeRecord_eq ops
      have hv2 : ∀ o ∈ bs ++ [ops.map (WriteOp.map toBytes)], validBatch o = true := by
        intro o ho; simp at ho; rcases ho with ho | rfl
        · exact hv o ho
        · exact hvb
      simp only [bind_run, append_run, hrec]
      cases hf1 : (nextFault fs).1 with
      | ok =>
        simp only [↓reduceIte, bind_run, sync_run]
        cases hf2 : (nextFault (nextFault fs).2).1 with
        | ok =>
          simp only [↓reduceIte, pure_run]
          left
          refine ⟨⟨rfl, ⟨bs ++ [ops.map (WriteOp.map toBytes)], hv2, by simp [encodeLog], hs'.symm⟩,
            by simp [e1], hb', by rw [← e1]; exact step_wellFormed hw _ |> fun h => by rw [e1] at *; exact h⟩,
            by rw [← e2]; rfl, fun h0 => by subst h0; rfl⟩
        | fail k =>
          simp only [Bool.false_eq_true, ↓reduceIte, pure_run]
          right
          refine ⟨fun h0 => by subst h0; simp [nextFault] at hf2, by trivial, by trivial, fun ch => ?_⟩
          rw [hs', ← hrs]
          exact inflight_crash hv hvb (List.prefix_refl _) ch
      | fail k =>
        simp only [Bool.false_eq_true, ↓reduceIte, pure_run]
        right
        refine ⟨fun h0 => by subst h0; simp [nextFault] at hf1, by trivial, by trivial, fun ch => ?_⟩
        rw [hs', ← hrs]
        exact inflight_crash hv hvb (List.take_prefix _ _) ch
    | _ =>
      have hs' := nowrite_state (s := s) (x := x) (fun ops' h => by
        rw [← e2]; simp [Response.map])
      simp only [pure_run]
      left
      refine ⟨⟨rfl, ⟨bs, hv, rfl, by rw [hrs, hs']⟩, by simp [e1], hb', by rw [hs']; exact hw⟩,
        by rw [← e2]; exact ofResponse_matches _, fun h0 => h0⟩

/-! ### Whole sessions -/

theorem execAll_failed {h : Handle} (hf : h.failed = true) :
    ∀ (cmds : List (Cmd ByteArray)) (st : FsState),
      (execAllWith (m := FsM) Core.exec h cmds).run st =
        ((h, cmds.map fun _ => .ioError (Core.ioDetail "store failed; reopen")), st)
  | [], st => rfl
  | c :: cs, st => by
    have ih := execAll_failed hf cs st
    unfold execAllWith
    rw [bind_run]
    have e : (Core.exec h c : FsM _).run st = ((h, .ioError (Core.ioDetail "store failed; reopen")), st) := by
      unfold Core.exec; simp [hf]; rfl
    rw [e]; simp only [bind_run, ih, pure_run, List.map_cons]

theorem repliesMatch_cons (r : Reply ByteArray) (rs : List (Reply ByteArray)) (x : Response Bytes)
    (xs : List (Response Bytes)) :
    repliesMatch (r :: rs) (x :: xs) = ((r.map toBytes).matches x && repliesMatch rs xs) := rfl

theorem runFrom_cons (s : Store) (c : Cmd Bytes) (cs : List (Cmd Bytes)) :
    runFrom s (c :: cs) = ((runFrom (step s c).1 cs).1, (step s c).2 :: (runFrom (step s c).1 cs).2) := rfl

/-- Sessions after a successful open: the crash-consistency shape, and the no-fault shape. -/
theorem execAll_spec : ∀ (cmds : List (Cmd ByteArray)) {h : Handle} {st : FsState} {s : Store},
    Good h st s →
    let scmds := cmds.map (Cmd.map toBytes)
    let out := (execAllWith (m := FsM) Core.exec h cmds).run st
    (∃ j ≤ cmds.length,
        out.1.2.length = cmds.length ∧
        repliesMatch (out.1.2.take j) ((runFrom s scmds).2.take j) = true ∧
        (∀ r ∈ out.1.2.drop j, r.isIOError = true) ∧
        ∀ ch, logState (crashOutcome out.2.disk ch) = some (runFrom s (scmds.take j)).1 ∨
          (j < cmds.length ∧ logState (crashOutcome out.2.disk ch) = some (runFrom s (scmds.take (j + 1))).1)) ∧
      (st.faults = [] → Good out.1.1 out.2 (runFrom s scmds).1 ∧
        repliesMatch out.1.2 (runFrom s scmds).2 = true ∧ out.2.faults = [])
  | [], h, st, s, hg => by
    simp only [execAllWith, pure_run]
    refine ⟨⟨0, Nat.le_refl _, rfl, rfl, by simp, fun ch => Or.inl (clean_crash hg.2.1 ch)⟩,
      fun h0 => ⟨hg, rfl, h0⟩⟩
  | x :: xs, h, st, s, hg => by
    have hex := exec_spec hg x
    unfold execAllWith
    simp only [bind_run]
    generalize hout1 : (Core.exec h x : FsM _).run st = out1 at hex
    obtain ⟨⟨h1, r1⟩, st1⟩ := out1
    simp only at hex ⊢
    rcases hex with ⟨hg1, hm1, hnf1⟩ | ⟨hne, hio, hfl, hcr⟩
    · obtain ⟨⟨j, hj, hl, hm, hio', hcr'⟩, hnf⟩ := execAll_spec xs hg1
      generalize hout2 : (execAllWith (m := FsM) Core.exec h1 xs).run st1 = out2 at hj hl hm hio' hcr' hnf
      obtain ⟨⟨h2, rs⟩, st2⟩ := out2
      simp only [pure_run] at *
      refine ⟨⟨j + 1, by simp; omega, by simp [hl], ?_, ?_, fun ch => ?_⟩, fun h0 => ?_⟩
      · simp only [List.take_succ_cons, List.map_cons, runFrom_cons, repliesMatch_cons, hm1, hm,
          Bool.true_and]
      · intro r hr; simp at hr; exact hio' r hr
      · simp only [List.map_cons, List.take_succ_cons, runFrom_cons]
        rcases hcr' ch with e | ⟨hjl, e⟩
        · exact Or.inl e
        · exact Or.inr ⟨by simp; omega, e⟩
      · obtain ⟨g2, m2, f2⟩ := hnf (hnf1 h0)
        refine ⟨by simpa [runFrom_cons] using g2, ?_, f2⟩
        simp only [List.map_cons, runFrom_cons, repliesMatch_cons, hm1, m2, Bool.true_and]
    · rw [execAll_failed hfl xs st1]
      simp only [pure_run]
      refine ⟨⟨0, by simp, by simp, rfl, ?_, fun ch => ?_⟩, fun h0 => absurd h0 hne⟩
      · intro r hr; simp at hr; rcases hr with rfl | ⟨_, _, rfl⟩
        · exact hio
        · rfl
      · simp only [List.take_zero, List.map_cons, List.take_succ_cons, runFrom_cons, runFrom]
        rcases hcr ch with e | e
        · exact Or.inl e
        · exact Or.inr ⟨by simp, e⟩

/-! ### The store theorems for the core -/

theorem map_run {α β : Type} (f : α → β) (x : FsM α) (st : FsState) :
    (f <$> x).run st = (f (x.run st).1, (x.run st).2) := rfl

theorem good_of_open {s0 : Store} {h : Handle} {st : FsState}
    (ho : OpenOk s0 (.ok h, st)) : Good h st s0 := by
  obtain ⟨hc, hf, hi, hb, hw⟩ := ho; exact ⟨hf, hc, hi, hb, hw⟩

/-- Core version of `store_crash_consistent`. -/
theorem core_crash_consistent {c0 : Bytes} {s0 : Store} (hs0 : logState c0 = some s0)
    (cmds : List (Cmd ByteArray)) (φ : List Fault) (ch : CrashChoice) :
    let scmds := cmds.map (Cmd.map toBytes)
    let out := (sessionWith (m := FsM) Core.openStore Core.exec cmds).run (startState c0 φ)
    let c1 := crashOutcome out.2.disk ch
    match out.1 with
    | .error r => r.isIOError = true ∧ logState c1 = some s0
    | .ok (_, rs) => ∃ j ≤ cmds.length,
        rs.length = cmds.length ∧
        repliesMatch (rs.take j) ((runFrom s0 scmds).2.take j) = true ∧
        (∀ r ∈ rs.drop j, r.isIOError = true) ∧
        (logState c1 = some (runFrom s0 (scmds.take j)).1 ∨
          (j < cmds.length ∧ logState c1 = some (runFrom s0 (scmds.take (j + 1))).1)) := by
  have ho := (open_spec hs0 φ).1
  simp only [startState]
  unfold sessionWith
  rw [bind_run]
  generalize hop : (Core.openStore : FsM _).run ⟨⟨c0, c0⟩, φ⟩ = o at ho
  obtain ⟨res, st1⟩ := o
  cases res with
  | error r =>
    obtain ⟨hio, hcr⟩ := ho
    exact ⟨hio, hcr ch⟩
  | ok h =>
    have hg := good_of_open ho
    obtain ⟨⟨j, hj, hl, hm, hio, hcr⟩, -⟩ := execAll_spec cmds hg
    simp only [map_run]
    exact ⟨j, hj, hl, hm, hio, hcr ch⟩

/-- Core version of `store_no_faults`. -/
theorem core_no_faults {c0 : Bytes} {s0 : Store} (hs0 : logState c0 = some s0)
    (cmds : List (Cmd ByteArray)) :
    ∃ h rs, ((sessionWith (m := FsM) Core.openStore Core.exec cmds).run (startState c0 [])).1 = .ok (h, rs) ∧
      repliesMatch rs (runFrom s0 (cmds.map (Cmd.map toBytes))).2 = true ∧
      h.index.toList = (runFrom s0 (cmds.map (Cmd.map toBytes))).1 ∧
      h.index.height ≤ 3 * Nat.log2 (h.index.size + 1) + 2 := by
  obtain ⟨ho, hnf⟩ := open_spec hs0 []
  obtain ⟨h0, he, hfs⟩ := hnf rfl
  simp only [startState]
  unfold sessionWith
  rw [bind_run]
  generalize hop : (Core.openStore : FsM _).run ⟨⟨c0, c0⟩, []⟩ = o at ho he hfs
  obtain ⟨res, st1⟩ := o
  simp only at he hfs; subst he
  have hg := good_of_open ho
  obtain ⟨-, hnf2⟩ := execAll_spec cmds hg
  obtain ⟨⟨-, -, hi, hb, -⟩, hm, -⟩ := hnf2 hfs
  simp only [map_run]
  exact ⟨_, _, rfl, hm, hi, bal_height_le hb⟩

end LeanKV.Proofs
