import LeanKV.Spec.Bytes

/-!
# LeanKV spec: the reference state machine (R3–R9)

The meaning of every operation is defined here on the simplest possible state: a list of
(key, value) pairs kept sorted by key. Any implementation must answer exactly as `run`
does (R9). Usage errors (bad syntax), corruption and I/O errors are not part of the state
machine. They belong to the parser (R22) and the storage layer (R11/R12).
-/

namespace LeanKV.Spec

/-- English: One write inside a batch (R8): a put or a delete. -/
inductive WriteOp where
  /-- English: Set key `k` to value `v`. -/
  | put (k v : Bytes)
  /-- English: Remove key `k`, if it is present. -/
  | delete (k : Bytes)
  deriving Repr, DecidableEq

/-- English: The upper end of a scan range (R7): a key, which is excluded from the range,
or "unbounded". -/
inductive Upper where
  /-- English: The range stops just before key `hi`. -/
  | below (hi : Bytes)
  /-- English: The range runs to the last key. -/
  | unbounded
  deriving Repr, DecidableEq

/-- English: A command the state machine accepts (R4–R8). -/
inductive Cmd where
  /-- English: `get k` (R4). -/
  | get (k : Bytes)
  /-- English: `put k v` (R5). -/
  | put (k v : Bytes)
  /-- English: `delete k` (R6). -/
  | delete (k : Bytes)
  /-- English: `scan lo hi limit` (R7). -/
  | scan (lo : Bytes) (hi : Upper) (limit : Nat)
  /-- English: `batch [ops]` (R8). -/
  | batch (ops : List WriteOp)
  deriving Repr, DecidableEq

/-- English: The state machine's answer to a command. -/
inductive Response where
  /-- English: The write succeeded. -/
  | ok
  /-- English: `get` found this value. -/
  | value (v : Bytes)
  /-- English: `get` found nothing. -/
  | notFound
  /-- English: `scan` returned these pairs, in ascending key order. -/
  | pairs (kvs : List (Bytes × Bytes))
  /-- English: The command broke a size limit (R1, R7a, R8a). Nothing changed. -/
  | limitError
  deriving Repr, DecidableEq

/-- English: The reference state (R9): a list of (key, value) pairs. In every reachable
state the keys are strictly ascending, so each key appears at most once (R3); this is
stated as `Store.WellFormed` and proven to be preserved in `Properties`. -/
abbrev Store := List (Bytes × Bytes)

/-- English: The store starts out empty. -/
def Store.empty : Store := []

/-- English: The value stored under key `k`, if there is one. -/
def Store.lookup (s : Store) (k : Bytes) : Option Bytes :=
  match s.find? (fun p => p.1 == k) with
  | some p => some p.2
  | none => none

/-- English: Set key `k` to value `v`, keeping the list sorted. Walk past smaller keys,
replace the pair if `k` is already present, and otherwise insert before the first larger
key. -/
def Store.insert : Store → Bytes → Bytes → Store
  | [], k, v => [(k, v)]
  | (k', v') :: rest, k, v =>
    if bytesLt k k' then (k, v) :: (k', v') :: rest
    else if k == k' then (k, v) :: rest
    else (k', v') :: Store.insert rest k v

/-- English: Remove key `k`. If `k` is not present, nothing changes. -/
def Store.erase (s : Store) (k : Bytes) : Store :=
  s.filter (fun p => p.1 != k)

/-- English: Whether key `k` is below the upper end `hi` of a scan range. -/
def Upper.admits : Upper → Bytes → Bool
  | .below hi, k => bytesLt k hi
  | .unbounded, _ => true

/-- English: The pairs whose key is at least `lo` and below `hi`, in the store's
(ascending) order, keeping at most the first `limit` of them (R7). If `lo ≥ hi` or
`limit = 0`, the result is empty (R7a). -/
def Store.scan (s : Store) (lo : Bytes) (hi : Upper) (limit : Nat) : List (Bytes × Bytes) :=
  (s.filter (fun p => !bytesLt p.1 lo && hi.admits p.1)).take limit

/-- English: A scan's lower bound is valid when it is at most 1024 bytes. It may be empty,
which means "from the first key" (R7a). -/
def validLower (lo : Bytes) : Bool := lo.length ≤ maxKeyLen

/-- English: A scan's upper bound is valid when it is "unbounded" or a valid key (R7a). -/
def Upper.valid : Upper → Bool
  | .below hi => validKey hi
  | .unbounded => true

/-- English: A write inside a batch is valid when its key, and its value if it has one,
are within the R1 limits. -/
def WriteOp.valid : WriteOp → Bool
  | .put k v => validKey k && validValue v
  | .delete k => validKey k

/-- English: How many raw bytes a write counts against the batch size limit: key bytes
plus value bytes (R8a). -/
def WriteOp.size : WriteOp → Nat
  | .put k v => k.length + v.length
  | .delete k => k.length

/-- English: A batch is valid when it has at most 10,000 ops, every op is valid, and the
ops total at most 64 MiB (R8a). The empty batch is valid. -/
def validBatch (ops : List WriteOp) : Bool :=
  ops.length ≤ maxBatchOps && ops.all WriteOp.valid &&
    (ops.map WriteOp.size).sum ≤ maxBatchBytes

/-- English: The effect of one write on the store. -/
def WriteOp.apply (s : Store) : WriteOp → Store
  | .put k v => s.insert k v
  | .delete k => s.erase k

/-- English: Run a batch atomically (R8). If the batch is valid, apply its writes in order
and answer `ok`. Otherwise change nothing and answer `limitError`. -/
def runBatch (s : Store) (ops : List WriteOp) : Store × Response :=
  if validBatch ops then (ops.foldl WriteOp.apply s, .ok) else (s, .limitError)

/-- English: The reference meaning of one command (R4–R8): the new state and the answer.
`put` and `delete` are exactly one-op batches. A command that breaks a limit changes
nothing and answers `limitError`. -/
def step (s : Store) : Cmd → Store × Response
  | .get k =>
    if validKey k then
      (s, match s.lookup k with
          | some v => .value v
          | none => .notFound)
    else (s, .limitError)
  | .put k v => runBatch s [.put k v]
  | .delete k => runBatch s [.delete k]
  | .scan lo hi limit =>
    if validLower lo && hi.valid then (s, .pairs (s.scan lo hi limit))
    else (s, .limitError)
  | .batch ops => runBatch s ops

/-- English: Run commands one after another from state `s`, returning the final state and
every answer in order. -/
def runFrom (s : Store) : List Cmd → Store × List Response
  | [] => (s, [])
  | c :: cs =>
    let (s', r) := step s c
    let (s'', rs) := runFrom s' cs
    (s'', r :: rs)

/-- English: Determinism (R9): the answers to a sequence of commands on a fresh store. They
depend only on the commands, since `run` is a function of them alone. -/
def run (cmds : List Cmd) : List Response := (runFrom Store.empty cmds).2

end LeanKV.Spec
