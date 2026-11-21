import LeanKV.Spec.Contract

/-!
Spec critic for `Spec/Contract.lean` (Stage 2). Run with
`lake env lean LeanKV/SpecCritic/ContractCritic.lean`.

An honest implementation of `Impl.step` and several planted bugs are evaluated against the
conditions of `impl_run_eq`, `impl_toList_eq` and `impl_height_le` on pseudo-random command
sequences. The honest one must pass everything and each bug must be caught, which shows the
contract is satisfiable and has teeth.
-/

open LeanKV.Spec

inductive Bug | none | chain | scanInclusive | putNoOverwrite | reversed deriving DecidableEq

/-- Perfectly balanced tree from a sorted list. -/
def buildF : Nat → List (Bytes × Bytes) → Tree
  | 0, _ => .leaf
  | _, [] => .leaf
  | f + 1, l =>
    let m := l.length / 2
    let (k, v) := l[m]!
    .node 0 (buildF f (l.take m)) (ofBytes k) (ofBytes v) (buildF f (l.drop (m + 1)))

def build (l : List (Bytes × Bytes)) : Tree := buildF (l.length + 1) l

def chain : List (Bytes × Bytes) → Tree
  | [] => .leaf
  | (k, v) :: rest => .node 0 .leaf (ofBytes k) (ofBytes v) (chain rest)

def stepBug (bug : Bug) (t : Tree) (c : Cmd ByteArray) : Tree × Response ByteArray :=
  let s := if bug == .reversed then t.toList.reverse else t.toList
  let c' := c.map toBytes
  let (s', r) : Store × Response Bytes := match bug, c' with
    | .scanInclusive, .scan lo (.below hi) n =>
      (s, if validLower lo && validKey hi then
            .pairs ((s.filter fun p => !bytesLt p.1 lo && !bytesLt hi p.1).take n)
          else .limitError)
    | .putNoOverwrite, .put k v =>
      if (s.lookup k).isSome then (s, if validKey k && validValue v then .ok else .limitError)
      else step s c'
    | _, _ => step s c'
  let t' := match bug with
    | .chain => chain s'
    | .reversed => build s'.reverse
    | _ => build s'
  (t', r.map ofBytes)

def runBug (bug : Bug) (t : Tree) : List (Cmd ByteArray) → Tree × List (Response ByteArray)
  | [] => (t, [])
  | c :: cs => let (t', r) := stepBug bug t c; let (t'', rs) := runBug bug t' cs; (t'', r :: rs)

/-- The three contract conditions, checked on every prefix of `cmds`. -/
def holds (bug : Bug) (cmds : List (Cmd ByteArray)) : Bool :=
  (List.range (cmds.length + 1)).all fun n =>
    let cs := cmds.take n
    let (t, rs) := runBug bug .leaf cs
    rs.map (Response.map toBytes) == run (cs.map (Cmd.map toBytes)) &&
    t.toList == (runFrom Store.empty (cs.map (Cmd.map toBytes))).1 &&
    decide (t.height ≤ 3 * Nat.log2 (t.size + 1) + 2)

def lcg (x : Nat) : Nat := (x * 1103515245 + 12345) % 2147483648

def key (x : Nat) : ByteArray := ⟨#[(0x61 + x % 26).toUInt8]⟩

def genCmds (seed : Nat) : List (Cmd ByteArray) := Id.run do
  let mut x := seed
  let mut out := #[]
  for _ in [0:60] do
    x := lcg x
    let k := key (x / 7)
    let c : Cmd ByteArray := match x % 7 with
      | 0 | 1 | 2 => .put k (key (x / 50))
      | 3 => .delete k
      | 4 => .get k
      | 5 => .scan (key (x / 11)) (if x % 2 == 0 then .unbounded else .below (key (x / 13))) (x % 5)
      | _ => .batch [.put k (key (x / 17)), .delete (key (x / 19))]
    out := out.push c
  return out.toList

def report (bug : Bug) : Nat × Nat :=
  (List.range 300).foldl (fun (p, f) s => if holds bug (genCmds s) then (p + 1, f) else (p, f + 1)) (0, 0)

#eval [("honest", report .none), ("chain (unbalanced)", report .chain),
  ("scan includes hi", report .scanInclusive), ("put never overwrites", report .putNoOverwrite),
  ("tree in reverse order", report .reversed)]
