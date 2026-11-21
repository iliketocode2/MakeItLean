import LeanKV.Spec.Model

/-!
# LeanKV spec: requirement-level properties of the reference model

Each theorem restates a requirement from `REQUIREMENTS.md` as a property of the reference
model `step`. They are stated with `sorry` in Stage 1 and must be proven in Stage 2 (spec
validation). Proving them is how we check that the model means what the English says.
None of them mentions an implementation.
-/

namespace LeanKV.Spec

/-! ## R2: the key order -/

/-- English: No key is smaller than itself (R2). -/
theorem bytesLt_irrefl (a : Bytes) : bytesLt a a = false := sorry

/-- English: If a < b and b < c then a < c (R2). -/
theorem bytesLt_trans {a b c : Bytes} (hab : bytesLt a b = true) (hbc : bytesLt b c = true) :
    bytesLt a c = true := sorry

/-- English: Any two different keys are ordered one way or the other (R2). -/
theorem bytesLt_total {a b : Bytes} (h : a ≠ b) : bytesLt a b = true ∨ bytesLt b a = true :=
  sorry

/-! ## R3 and well-formedness of reachable states -/

/-- English: A store is well-formed when its keys are strictly ascending and every key and
value is within the R1 limits. -/
def Store.WellFormed (s : Store) : Prop :=
  s.Pairwise (fun a b => bytesLt a.1 b.1 = true) ∧
    ∀ p ∈ s, validKey p.1 = true ∧ validValue p.2 = true

/-- English: Every command takes a well-formed store to a well-formed store. -/
theorem step_wellFormed {s : Store} (hs : s.WellFormed) (c : Cmd) : (step s c).1.WellFormed :=
  sorry

/-- English: Every state reachable from the empty store is well-formed. -/
theorem runFrom_empty_wellFormed (cmds : List Cmd) :
    (runFrom Store.empty cmds).1.WellFormed := sorry

/-- English: In a well-formed store each key appears at most once (R3). -/
theorem wellFormed_keys_nodup {s : Store} (hs : s.WellFormed) : (s.map Prod.fst).Nodup :=
  sorry

/-! ## R1: limits -/

/-- English: A command that answers `limitError` changes nothing (R1, R7a, R8a). -/
theorem limitError_unchanged (s : Store) (c : Cmd) (h : (step s c).2 = .limitError) :
    (step s c).1 = s := sorry

/-- English: `get`, `put` and `delete` with an invalid key answer `limitError` (R1). -/
theorem invalid_key_rejected (s : Store) (k v : Bytes) (h : validKey k = false) :
    (step s (.get k)).2 = .limitError ∧ (step s (.put k v)).2 = .limitError ∧
      (step s (.delete k)).2 = .limitError := sorry

/-- English: `put` with a value over 1 MiB answers `limitError` (R1). -/
theorem invalid_value_rejected (s : Store) (k v : Bytes) (h : validValue v = false) :
    (step s (.put k v)).2 = .limitError := sorry

/-! ## R4: get -/

/-- English: `get` never changes anything (R4). -/
theorem get_unchanged (s : Store) (k : Bytes) : (step s (.get k)).1 = s := sorry

/-! ## R5: put -/

/-- English: A valid `put k v` succeeds, and afterwards `get k` returns `v` (R5). -/
theorem put_then_get {s : Store} (hs : s.WellFormed) {k v : Bytes}
    (hk : validKey k = true) (hv : validValue v = true) :
    (step s (.put k v)).2 = .ok ∧ (step (step s (.put k v)).1 (.get k)).2 = .value v := sorry

/-- English: `put k v` leaves every other key unchanged (R5). -/
theorem put_other {s : Store} (hs : s.WellFormed) {k k' v : Bytes} (hne : k' ≠ k) :
    (step s (.put k v)).1.lookup k' = s.lookup k' := sorry

/-! ## R6: delete -/

/-- English: A valid `delete k` succeeds, and afterwards `get k` is not found (R6). -/
theorem delete_then_get {s : Store} (hs : s.WellFormed) {k : Bytes} (hk : validKey k = true) :
    (step s (.delete k)).2 = .ok ∧ (step (step s (.delete k)).1 (.get k)).2 = .notFound :=
  sorry

/-- English: `delete k` leaves every other key unchanged (R6). -/
theorem delete_other {s : Store} (hs : s.WellFormed) {k k' : Bytes} (hne : k' ≠ k) :
    (step s (.delete k)).1.lookup k' = s.lookup k' := sorry

/-- English: Deleting a missing key does nothing (R6). -/
theorem delete_missing {s : Store} {k : Bytes} (h : s.lookup k = none) :
    (step s (.delete k)).1 = s := sorry

/-! ## R7: scan -/

/-- English: A scan with valid bounds succeeds and changes nothing, even when the result is
empty (R7a). -/
theorem scan_ok (s : Store) {lo : Bytes} {hi : Upper} (limit : Nat)
    (hlo : validLower lo = true) (hhi : hi.valid = true) :
    step s (.scan lo hi limit) = (s, .pairs (s.scan lo hi limit)) := sorry

/-- English: A scan returns at most `limit` pairs (R7). -/
theorem scan_length_le (s : Store) (lo : Bytes) (hi : Upper) (limit : Nat) :
    (s.scan lo hi limit).length ≤ limit := sorry

/-- English: On a well-formed store, a scan's result is in strictly ascending key order
(R7). -/
theorem scan_sorted {s : Store} (hs : s.WellFormed) (lo : Bytes) (hi : Upper) (limit : Nat) :
    (s.scan lo hi limit).Pairwise (fun a b => bytesLt a.1 b.1 = true) := sorry

/-- English: Every pair a scan returns is in the store, with key ≥ `lo` and below `hi`
(R7). -/
theorem scan_sound {s : Store} (hs : s.WellFormed) (lo : Bytes) (hi : Upper) (limit : Nat)
    {p : Bytes × Bytes} (hp : p ∈ s.scan lo hi limit) :
    bytesLt p.1 lo = false ∧ hi.admits p.1 = true ∧ s.lookup p.1 = some p.2 := sorry

/-- English: A scan leaves out an in-range pair only when the limit was reached and that pair's
key is larger than every key returned. So the scan returns the *first* `limit` pairs in
range (R7). -/
theorem scan_complete {s : Store} (hs : s.WellFormed) (lo : Bytes) (hi : Upper)
    (limit : Nat) {k v : Bytes} (hkv : s.lookup k = some v) (hlo : bytesLt k lo = false)
    (hhi : hi.admits k = true) (hout : (k, v) ∉ s.scan lo hi limit) :
    (s.scan lo hi limit).length = limit ∧
      ∀ p ∈ s.scan lo hi limit, bytesLt p.1 k = true := sorry

/-- English: A scan with `limit = 0` returns nothing (R7a). -/
theorem scan_limit_zero (s : Store) (lo : Bytes) (hi : Upper) : s.scan lo hi 0 = [] := sorry

/-- English: A scan with `lo ≥ hi` returns nothing (R7a). -/
theorem scan_empty_range (s : Store) {lo hi : Bytes} (h : bytesLt lo hi = false)
    (limit : Nat) : s.scan lo (.below hi) limit = [] := sorry

/-! ## R8: batch -/

/-- English: The single-command form of a write: `put k v` or `delete k`. -/
def WriteOp.toCmd : WriteOp → Cmd
  | .put k v => .put k v
  | .delete k => .delete k

/-- English: An invalid batch changes nothing and answers `limitError`. No write in it takes
effect (R8 atomicity, R8a). -/
theorem batch_invalid (s : Store) {ops : List WriteOp} (h : validBatch ops = false) :
    step s (.batch ops) = (s, .limitError) := sorry

/-- English: A valid batch has exactly the effect of running its writes one at a time, in
order, and each of those writes succeeds (R8). This is also the licence for group commit
(R18). -/
theorem batch_serial (s : Store) {ops : List WriteOp} (h : validBatch ops = true) :
    step s (.batch ops) = ((runFrom s (ops.map WriteOp.toCmd)).1, .ok) ∧
      (runFrom s (ops.map WriteOp.toCmd)).2 = ops.map (fun _ => Response.ok) := sorry

end LeanKV.Spec
