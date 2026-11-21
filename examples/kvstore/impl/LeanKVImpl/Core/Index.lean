import LeanKV.Spec.Contract

/-!
# LeanKV core: the in-memory index (Stage 3)

An AVL tree on the spec's `Tree` type. Each node's spare `bal` field holds its height. Keys and
values are `ByteArray`s. `Core.step` is the intended filling of the spec hole `Impl.step`;
Stage 4 proves it against `impl_run_eq`, `impl_toList_eq` and `impl_height_le`.
-/

namespace LeanKV.Core
open LeanKV.Spec

/-! ## Byte-string order -/

/-- Compare byte strings from position `i` on, bytewise, shorter-prefix-first (spec `bytesLt`). -/
def cmpFrom (a b : ByteArray) (i : Nat) : Ordering :=
  if ha : i < a.size then
    if hb : i < b.size then
      let x := a[i]
      let y := b[i]
      if x < y then .lt else if y < x then .gt else cmpFrom a b (i + 1)
    else .gt
  else if i < b.size then .lt else .eq
termination_by a.size - i

/-- Bytewise lexicographic comparison of two byte strings. -/
def cmpBytes (a b : ByteArray) : Ordering := cmpFrom a b 0

/-- `a < b` in the key order. -/
def ltBytes (a b : ByteArray) : Bool := cmpBytes a b == .lt

/-! ## AVL tree -/

/-- The cached height of a tree. -/
def ht : Tree → Nat
  | .leaf => 0
  | .node h _ _ _ _ => h

/-- A node with its height computed from its children. -/
def mk (l : Tree) (k v : ByteArray) (r : Tree) : Tree :=
  .node (max (ht l) (ht r) + 1) l k v r

/-- Rebuild a node whose children's heights differ by at most 2, restoring the AVL balance. -/
def balance (l : Tree) (k v : ByteArray) (r : Tree) : Tree :=
  if ht r + 1 < ht l then
    match l with
    | .node _ ll lk lv lr =>
      if ht lr ≤ ht ll then mk ll lk lv (mk lr k v r)
      else match lr with
        | .node _ lrl lrk lrv lrr => mk (mk ll lk lv lrl) lrk lrv (mk lrr k v r)
        | .leaf => mk l k v r
    | .leaf => mk l k v r
  else if ht l + 1 < ht r then
    match r with
    | .node _ rl rk rv rr =>
      if ht rl ≤ ht rr then mk (mk l k v rl) rk rv rr
      else match rl with
        | .node _ rll rlk rlv rlr => mk (mk l k v rll) rlk rlv (mk rlr rk rv rr)
        | .leaf => mk l k v r
    | .leaf => mk l k v r
  else mk l k v r

/-- The value stored under `k`, if any. -/
def lookup (t : Tree) (k : ByteArray) : Option ByteArray :=
  match t with
  | .leaf => none
  | .node _ l k' v r =>
    match cmpBytes k k' with
    | .lt => lookup l k
    | .gt => lookup r k
    | .eq => some v

/-- Set `k` to `v`. -/
def insert (t : Tree) (k v : ByteArray) : Tree :=
  match t with
  | .leaf => mk .leaf k v .leaf
  | .node h l k' v' r =>
    match cmpBytes k k' with
    | .lt => balance (insert l k v) k' v' r
    | .gt => balance l k' v' (insert r k v)
    | .eq => .node h l k v r

/-- Remove the smallest key, returning it, its value and the remaining tree. -/
def removeMin : Tree → Option (ByteArray × ByteArray × Tree)
  | .leaf => none
  | .node _ l k v r =>
    match removeMin l with
    | none => some (k, v, r)
    | some (mk', mv, l') => some (mk', mv, balance l' k v r)

/-- Remove `k`, if present. -/
def erase (t : Tree) (k : ByteArray) : Tree :=
  match t with
  | .leaf => .leaf
  | .node _ l k' v r =>
    match cmpBytes k k' with
    | .lt => balance (erase l k) k' v r
    | .gt => balance l k' v (erase r k)
    | .eq =>
      match removeMin r with
      | none => l
      | some (mk', mv, r') => balance l mk' mv r'

/-- Whether key `k` is below a scan's upper end. -/
def admits (hi : Upper ByteArray) (k : ByteArray) : Bool :=
  match hi with
  | .below h => ltBytes k h
  | .unbounded => true

/-- In-order scan from `lo` up to `hi`, appending to `acc` until it holds `limit` pairs. Prunes
subtrees that lie entirely outside the range. -/
def scanAux (lo : ByteArray) (hi : Upper ByteArray) (limit : Nat) :
    Tree → Array (ByteArray × ByteArray) → Array (ByteArray × ByteArray)
  | .leaf, acc => acc
  | .node _ l k v r, acc =>
    if limit ≤ acc.size then acc
    else if ltBytes k lo then scanAux lo hi limit r acc
    else
      let acc := scanAux lo hi limit l acc
      if limit ≤ acc.size then acc
      else if admits hi k then scanAux lo hi limit r (acc.push (k, v)) else acc

/-- The pairs with `lo ≤ key < hi`, ascending, at most `limit` of them. -/
def scan (t : Tree) (lo : ByteArray) (hi : Upper ByteArray) (limit : Nat) :
    List (ByteArray × ByteArray) :=
  (scanAux lo hi limit t #[]).toList

/-! ## Limits and the step function -/

/-- R1: a key is 1–1024 bytes. -/
def validKeyB (k : ByteArray) : Bool := 1 ≤ k.size && k.size ≤ maxKeyLen

/-- R1: a value is at most 1 MiB. -/
def validValueB (v : ByteArray) : Bool := v.size ≤ maxValueLen

/-- R1 for a single write. -/
def opValid : WriteOp ByteArray → Bool
  | .put k v => validKeyB k && validValueB v
  | .delete k => validKeyB k

/-- R8a: raw bytes a write counts against the batch limit. -/
def opSize : WriteOp ByteArray → Nat
  | .put k v => k.size + v.size
  | .delete k => k.size

/-- R8a: a batch is valid when it has at most 10,000 valid ops totalling at most 64 MiB. -/
def batchValid (ops : List (WriteOp ByteArray)) : Bool :=
  ops.length ≤ maxBatchOps && ops.all opValid && (ops.map opSize).sum ≤ maxBatchBytes

/-- Apply one write to the index. -/
def applyOp (t : Tree) : WriteOp ByteArray → Tree
  | .put k v => insert t k v
  | .delete k => erase t k

/-- Run a batch atomically: all writes in order, or nothing on a limit error. -/
def runBatch (t : Tree) (ops : List (WriteOp ByteArray)) : Tree × Response ByteArray :=
  if batchValid ops then (ops.foldl applyOp t, .ok) else (t, .limitError)

/-- The implementation of one command on the index. Intended filling of `Impl.step`. -/
def step (t : Tree) : Cmd ByteArray → Tree × Response ByteArray
  | .get k =>
    if validKeyB k then
      (t, match lookup t k with
          | some v => .value v
          | none => .notFound)
    else (t, .limitError)
  | .put k v => runBatch t [.put k v]
  | .delete k => runBatch t [.delete k]
  | .scan lo hi limit =>
    let hiOk := match hi with
      | .below h => validKeyB h
      | .unbounded => true
    if lo.size ≤ maxKeyLen && hiOk then (t, .pairs (scan t lo hi limit)) else (t, .limitError)
  | .batch ops => runBatch t ops

end LeanKV.Core
