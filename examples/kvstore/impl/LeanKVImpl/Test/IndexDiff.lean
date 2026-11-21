import LeanKVImpl.Core.Index
/-! Differential test of `Core.step` against the contract conditions (Stage 3).
Run: `lake env lean LeanKVImpl/Test/IndexDiff.lean` -/
open LeanKV.Spec LeanKV.Core

def runCore (t : Tree) : List (Cmd ByteArray) → Tree × List (Response ByteArray)
  | [] => (t, [])
  | c :: cs => let (t', r) := step t c; let (t'', rs) := runCore t' cs; (t'', r :: rs)

def lcg (x : Nat) : Nat := (x * 1103515245 + 12345) % 2147483648
def key (x : Nat) : ByteArray :=
  if x % 9 == 0 then ⟨#[(0x61 + x % 8).toUInt8, (0x61 + x / 8 % 8).toUInt8]⟩ else ⟨#[(0x61 + x % 64).toUInt8]⟩

def genCmds (seed len : Nat) : List (Cmd ByteArray) := Id.run do
  let mut x := seed
  let mut out := #[]
  for _ in [0:len] do
    x := lcg x
    let k := key (x / 7)
    let c : Cmd ByteArray := match x % 9 with
      | 0 | 1 | 2 | 3 => .put k (key (x / 50))
      | 4 => .delete k
      | 5 => .get k
      | 6 => .scan (if x % 3 == 0 then ByteArray.empty else key (x / 11))
               (if x % 2 == 0 then .unbounded else .below (key (x / 13))) (x / 3 % 12)
      | 7 => .batch [.put k (key (x / 17)), .delete (key (x / 19)), .put (key (x / 23)) ByteArray.empty]
      | _ => if x % 5 == 0 then .put ByteArray.empty k else .delete (key (x / 29))
    out := out.push c
  return out.toList

/-- All three contract conditions at the end of the sequence, plus answers at every step. -/
def check (cmds : List (Cmd ByteArray)) : Bool :=
  let (t, rs) := runCore .leaf cmds
  let scmds := cmds.map (Cmd.map toBytes)
  rs.map (Response.map toBytes) == run scmds &&
  t.toList == (runFrom Store.empty scmds).1 &&
  decide (t.height ≤ 3 * Nat.log2 (t.size + 1) + 2)

#eval
  let results := (List.range 300).map fun s => check (genCmds s 200)
  (results.filter id |>.length, results.filter (! ·) |>.length,
   (runCore .leaf (genCmds 7 200)).1.size, (runCore .leaf (genCmds 7 200)).1.height)
