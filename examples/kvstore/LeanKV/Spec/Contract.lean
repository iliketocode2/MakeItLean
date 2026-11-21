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
value, plus a spare number the implementation may use for balancing data (a height, a size
or a colour). -/
inductive Tree where
  /-- English: The empty tree. -/
  | leaf
  /-- English: A node with balancing data `bal`, a left subtree, a key and value, and a right
  subtree. -/
  | node (bal : Nat) (left : Tree) (key value : Bytes) (right : Tree)
  deriving Repr, DecidableEq

/-- English: The tree's height: 0 for the empty tree, otherwise one more than the taller
subtree. -/
def Tree.height : Tree → Nat
  | .leaf => 0
  | .node _ l _ _ r => max l.height r.height + 1

/-- English: The (key, value) pairs of the tree read left to right (in-order). The
implementation must keep this equal to the reference store. -/
def Tree.toList : Tree → List (Bytes × Bytes)
  | .leaf => []
  | .node _ l k v r => l.toList ++ (k, v) :: r.toList

/-- English: The number of keys in the tree. -/
def Tree.size (t : Tree) : Nat := t.toList.length

/-- English: IMPLEMENTATION HOLE. The implementation's meaning of one command on the index:
the new tree and the answer. The implementer fills this in; nothing else may change. -/
def Impl.step : Tree → Cmd → Tree × Response := sorry

/-- English: Run commands one after another on the index with `Impl.step`, starting from
tree `t`, and return the final tree and every answer in order. -/
def Impl.runFrom (t : Tree) : List Cmd → Tree × List Response
  | [] => (t, [])
  | c :: cs =>
    let (t', r) := Impl.step t c
    let (t'', rs) := Impl.runFrom t' cs
    (t'', r :: rs)

/-- English: The implementation's answers to a sequence of commands, starting from the empty
tree. -/
def Impl.run (cmds : List Cmd) : List Response := (Impl.runFrom .leaf cmds).2

/-- English: End-to-end correctness (R4–R9). For every sequence of commands, the
implementation gives exactly the same answers as the reference model. -/
theorem impl_run_eq (cmds : List Cmd) : Impl.run cmds = run cmds := sorry

/-- English: Abstraction (R3, R9). After any sequence of commands, the tree read left to right
is exactly the reference store. So the tree really holds the data, in ascending key order. -/
theorem impl_toList_eq (cmds : List Cmd) :
    (Impl.runFrom .leaf cmds).1.toList = (runFrom Store.empty cmds).1 := sorry

/-- English: Balance (R17). After any sequence of commands, the tree's height is at most
3·⌊log₂(n+1)⌋ + 2, where n is the number of keys. This covers AVL, red-black and
weight-balanced trees. -/
theorem impl_height_le (cmds : List Cmd) :
    (Impl.runFrom .leaf cmds).1.height ≤
      3 * Nat.log2 ((Impl.runFrom .leaf cmds).1.size + 1) + 2 := sorry

end LeanKV.Spec
