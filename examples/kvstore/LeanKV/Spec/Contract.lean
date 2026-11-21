import LeanKV.Spec.Model

/-!
# LeanKV spec: the implementation contract (R9, R17)

This is the part of the spec an implementation must satisfy, written as in the DeepMind
workflow: one typed `sorry` hole (`Impl.step`) for the implementer to fill, plus the theorems
the filled-in hole must satisfy. After freezing, the comparator checks that these statements
and every definition they depend on are unchanged. `Impl.step` is the only declaration that
may differ.

Why the index shape is fixed here (user decision, 2026-11-21): R17's height bound can only be
enforced on a shape the spec can see. Otherwise "height" could be defined as 0. The
abstraction theorem forces the tree to really hold the data in key order, which rules out
packing the whole store into one node.

Known residual gap (accepted with R17): the theorems constrain the tree's *shape*, not how
the operations *use* it. An implementation could keep a balanced tree but answer `get` by
an O(n) walk. Wall-clock cost is benchmarked (R17, R19), not proven.
-/

namespace LeanKV.Spec

/-- English: The in-memory index (R17): a binary search tree. Each node holds one key and its
value as `ByteArray`s (fast, compact), plus a spare number the implementation may use for
balancing data (a height, a size or a colour). -/
inductive Tree where
  /-- English: The empty tree. -/
  | leaf
  /-- English: A node with balancing data `bal`, a left subtree, a key and value, and a right
  subtree. -/
  | node (bal : Nat) (left : Tree) (key value : ByteArray) (right : Tree)

/-- English: The tree's height: 0 for the empty tree, otherwise one more than the taller
subtree. -/
def Tree.height : Tree → Nat
  | .leaf => 0
  | .node _ l _ _ r => max l.height r.height + 1

/-- English: The (key, value) pairs of the tree read left to right (in-order), as spec bytes.
The implementation must keep this equal to the reference store. -/
def Tree.toList : Tree → List (Bytes × Bytes)
  | .leaf => []
  | .node _ l k v r => l.toList ++ (toBytes k, toBytes v) :: r.toList

/-- English: The number of keys in the tree. -/
def Tree.size (t : Tree) : Nat := t.toList.length

/-- English: IMPLEMENTATION HOLE. The implementation's meaning of one command on the index,
working on `ByteArray`s: the new tree and the answer. The implementer fills this in; nothing
else may change. -/
def Impl.step : Tree → Cmd ByteArray → Tree × Response ByteArray := sorry

/-- English: Run commands one after another with step function `st` on the index, starting
from tree `t`, and return the final tree and every answer in order. The theorems below apply it
to the implementation hole `Impl.step`. Spec definitions never call a hole themselves; only
theorems name holes. -/
def runTree (st : Tree → Cmd ByteArray → Tree × Response ByteArray) (t : Tree) :
    List (Cmd ByteArray) → Tree × List (Response ByteArray)
  | [] => (t, [])
  | c :: cs =>
    let (t', r) := st t c
    let (t'', rs) := runTree st t' cs
    (t'', r :: rs)

/-- English: End-to-end correctness (R4–R9). For every sequence of commands, the
implementation's answers, read as spec bytes, are exactly the reference model's answers to the
same commands. -/
theorem impl_run_eq (cmds : List (Cmd ByteArray)) :
    (runTree Impl.step .leaf cmds).2.map (Response.map toBytes) = run (cmds.map (Cmd.map toBytes)) :=
    sorry

/-- English: Abstraction (R3, R9). After any sequence of commands, the tree read left to right
is exactly the reference store. So the tree really holds the data, in ascending key order. -/
theorem impl_toList_eq (cmds : List (Cmd ByteArray)) :
    (runTree Impl.step .leaf cmds).1.toList = (runFrom Store.empty (cmds.map (Cmd.map toBytes))).1 :=
  sorry

/-- English: Balance (R17). After any sequence of commands, the tree's height is at most
3·⌊log₂(n+1)⌋ + 2, where n is the number of keys. This covers AVL, red-black and
weight-balanced trees. -/
theorem impl_height_le (cmds : List (Cmd ByteArray)) :
    (runTree Impl.step .leaf cmds).1.height ≤
      3 * Nat.log2 ((runTree Impl.step .leaf cmds).1.size + 1) + 2 := sorry

end LeanKV.Spec
