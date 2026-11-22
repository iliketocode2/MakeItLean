import LeanKVImpl.Proofs.Session
import LeanKVImpl.Core.Substrate

/-!
# Substrate theorems: crash consistency for adaptive clients (Phase 2)

For any app whose commands become KV commands through `pick` (chosen from the current state),
a session on the model file system answers like the reference run `runPick`, blocks itself after
an I/O error, and after any crash recovers exactly the acknowledged prefix, plus possibly the
command in flight. With no faults it answers exactly like `runPick`.
-/

set_option linter.deprecated false

namespace LeanKV.Proofs
open LeanKV.Spec

/-- English: The reference run of an adaptive client: each app command `c` becomes the KV command
`pick s c` for the current reference store `s`. -/
def runPick {C : Type} (pick : Store → C → Cmd Bytes) (s : Store) : List C → Store × List (Response Bytes)
  | [] => (s, [])
  | c :: cs => ((runPick pick (step s (pick s c)).1 cs).1,
                (step s (pick s c)).2 :: (runPick pick (step s (pick s c)).1 cs).2)

/-- `pickI` (on the index) implements `pick` (on the reference store), on every well-formed
index (the store only ever holds well-formed ones). -/
def PickOk {C : Type} (pickI : Tree → C → Cmd ByteArray) (pick : Store → C → Cmd Bytes) : Prop :=
  ∀ t c, Store.WellFormed t.toList → (pickI t c).map toBytes = pick t.toList c

theorem execPick_failed {C : Type} (pickI : Tree → C → Cmd ByteArray) {h : Handle} (hf : h.failed = true) :
    ∀ (cs : List C) (st : FsState),
      (Core.execPick (m := FsM) pickI h cs).run st =
        ((h, cs.map fun _ => .ioError (Core.ioDetail "store failed; reopen")), st)
  | [], st => rfl
  | c :: cs, st => by
    have ih := execPick_failed pickI hf cs st
    unfold Core.execPick
    rw [bind_run]
    have e : (Core.exec h (pickI h.index c) : FsM _).run st =
        ((h, .ioError (Core.ioDetail "store failed; reopen")), st) := by
      unfold Core.exec; simp [hf]; rfl
    rw [e]; simp only [bind_run, ih, pure_run, List.map_cons]

/-- Adaptive sessions after a successful open: crash consistency, and exact answers without faults. -/
theorem execPick_spec {C : Type} {pickI : Tree → C → Cmd ByteArray} {pick : Store → C → Cmd Bytes}
    (hp : PickOk pickI pick) : ∀ (cs : List C) {h : Handle} {st : FsState} {s : Store},
    Good h st s →
    let out := (Core.execPick (m := FsM) pickI h cs).run st
    (∃ j ≤ cs.length,
        out.1.2.length = cs.length ∧
        repliesMatch (out.1.2.take j) ((runPick pick s cs).2.take j) = true ∧
        (∀ r ∈ out.1.2.drop j, r.isIOError = true) ∧
        ∀ ch, logState (crashOutcome out.2.disk ch) = some (runPick pick s (cs.take j)).1 ∨
          (j < cs.length ∧ logState (crashOutcome out.2.disk ch) = some (runPick pick s (cs.take (j + 1))).1)) ∧
      (st.faults = [] → Good out.1.1 out.2 (runPick pick s cs).1 ∧
        repliesMatch out.1.2 (runPick pick s cs).2 = true ∧ out.2.faults = [])
  | [], h, st, s, hg => by
    simp only [Core.execPick, pure_run]
    refine ⟨⟨0, Nat.le_refl _, rfl, rfl, by simp, fun ch => Or.inl (clean_crash hg.2.1 ch)⟩,
      fun h0 => ⟨hg, rfl, h0⟩⟩
  | x :: xs, h, st, s, hg => by
    have hpx : (pickI h.index x).map toBytes = pick s x := by
      rw [hp _ _ (by rw [hg.2.2.1]; exact hg.2.2.2.2), hg.2.2.1]
    have hex := exec_spec hg (pickI h.index x)
    rw [hpx] at hex
    unfold Core.execPick
    simp only [bind_run]
    generalize hout1 : (Core.exec h (pickI h.index x) : FsM _).run st = out1 at hex
    obtain ⟨⟨h1, r1⟩, st1⟩ := out1
    simp only at hex ⊢
    rcases hex with ⟨hg1, hm1, hnf1⟩ | ⟨hne, hio, hfl, hcr⟩
    · obtain ⟨⟨j, hj, hl, hm, hio', hcr'⟩, hnf⟩ := execPick_spec hp xs hg1
      generalize hout2 : (Core.execPick (m := FsM) pickI h1 xs).run st1 = out2 at hj hl hm hio' hcr' hnf
      obtain ⟨⟨h2, rs⟩, st2⟩ := out2
      simp only [pure_run] at *
      refine ⟨⟨j + 1, by simp; omega, by simp [hl], ?_, ?_, fun ch => ?_⟩, fun h0 => ?_⟩
      · simp only [List.take_succ_cons, runPick, repliesMatch_cons, hm1, hm, Bool.true_and]
      · intro r hr; simp at hr; exact hio' r hr
      · simp only [List.take_succ_cons, runPick]
        rcases hcr' ch with e | ⟨hjl, e⟩
        · exact Or.inl e
        · exact Or.inr ⟨by simp; omega, e⟩
      · obtain ⟨g2, m2, f2⟩ := hnf (hnf1 h0)
        refine ⟨by simpa [runPick] using g2, ?_, f2⟩
        simp only [runPick, repliesMatch_cons, hm1, m2, Bool.true_and]
    · rw [execPick_failed pickI hfl xs st1]
      simp only [pure_run]
      refine ⟨⟨0, by simp, by simp, rfl, ?_, fun ch => ?_⟩, fun h0 => absurd h0 hne⟩
      · intro r hr; simp at hr; rcases hr with rfl | ⟨_, _, rfl⟩
        · exact hio
        · rfl
      · simp only [List.take_zero, List.take_succ_cons, runPick]
        rcases hcr ch with e | e
        · exact Or.inl e
        · exact Or.inr ⟨by simp, e⟩

/-- **The substrate theorem.** Open the store on a healthy log, then run app commands through
`pickI`, under any I/O faults, and crash in any allowed way. Either open fails with an I/O
error and the log still stands for the starting store, or: the replies match the reference run
`runPick` up to some command j and are I/O errors after it, and the log after the crash stands
for the reference store after j commands, or after j+1. -/
theorem substrate_crash_consistent {C : Type} {pickI : Tree → C → Cmd ByteArray}
    {pick : Store → C → Cmd Bytes} (hp : PickOk pickI pick) {c0 : Bytes} {s0 : Store}
    (hs0 : logState c0 = some s0) (cs : List C) (φ : List Fault) (ch : CrashChoice) :
    let out := (do
        match ← (Core.openStore : FsM _) with
        | .error r => pure (Except.error r)
        | .ok h => Except.ok <$> Core.execPick pickI h cs : FsM _).run (startState c0 φ)
    let c1 := crashOutcome out.2.disk ch
    match out.1 with
    | .error r => r.isIOError = true ∧ logState c1 = some s0
    | .ok (_, rs) => ∃ j ≤ cs.length,
        rs.length = cs.length ∧
        repliesMatch (rs.take j) ((runPick pick s0 cs).2.take j) = true ∧
        (∀ r ∈ rs.drop j, r.isIOError = true) ∧
        (logState c1 = some (runPick pick s0 (cs.take j)).1 ∨
          (j < cs.length ∧ logState c1 = some (runPick pick s0 (cs.take (j + 1))).1)) := by
  have ho := (open_spec hs0 φ).1
  simp only [startState]
  rw [bind_run]
  generalize hop : (Core.openStore : FsM _).run ⟨⟨c0, c0⟩, φ⟩ = o at ho
  obtain ⟨res, st1⟩ := o
  cases res with
  | error r => obtain ⟨hio, hcr⟩ := ho; exact ⟨hio, hcr ch⟩
  | ok h =>
    obtain ⟨⟨j, hj, hl, hm, hio, hcr⟩, -⟩ := execPick_spec hp cs (good_of_open ho)
    simp only [map_run]
    exact ⟨j, hj, hl, hm, hio, hcr ch⟩

/-- **The substrate theorem without faults:** every reply matches the reference run, and the
index holds exactly its final store. -/
theorem substrate_no_faults {C : Type} {pickI : Tree → C → Cmd ByteArray}
    {pick : Store → C → Cmd Bytes} (hp : PickOk pickI pick) {c0 : Bytes} {s0 : Store}
    (hs0 : logState c0 = some s0) (cs : List C) :
    ∃ h rs, ((do
        match ← (Core.openStore : FsM _) with
        | .error r => pure (Except.error r)
        | .ok h => Except.ok <$> Core.execPick pickI h cs : FsM _).run (startState c0 [])).1 = .ok (h, rs) ∧
      repliesMatch rs (runPick pick s0 cs).2 = true ∧ h.index.toList = (runPick pick s0 cs).1 := by
  obtain ⟨ho, hnf⟩ := open_spec hs0 []
  obtain ⟨h0, he, hfs⟩ := hnf rfl
  simp only [startState]
  rw [bind_run]
  generalize hop : (Core.openStore : FsM _).run ⟨⟨c0, c0⟩, []⟩ = o at ho he hfs
  obtain ⟨res, st1⟩ := o
  simp only at he hfs; subst he
  obtain ⟨-, hnf2⟩ := execPick_spec hp cs (good_of_open ho)
  obtain ⟨⟨-, -, hi, -, -⟩, hm, -⟩ := hnf2 hfs
  simp only [map_run]
  exact ⟨_, _, rfl, hm, hi⟩

end LeanKV.Proofs
