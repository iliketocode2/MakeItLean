import LeanKVImpl.Core.Store
import LeanKVSol.Base.Wire

/-! Stage 7: which layer overflows the stack on large-but-valid inputs? Run one stage per process. -/
open LeanKV.Spec

def val (n : Nat) : ByteArray := ⟨(Array.range n).map fun i => (0x61 + i % 26).toUInt8⟩

def main (args : List String) : IO Unit := do
  let stage := args.headD "parse"
  let nOps := (args.drop 1).headD "10000" |>.toNat!
  let vlen := (args.drop 2).headD "6000" |>.toNat!
  let ops : List (WriteOp ByteArray) := (List.range nOps).map fun i => .put s!"k{i}".toUTF8 (val vlen)
  match stage with
  | "parse" =>
    let line := "batch " ++ " ".intercalate ((List.range nOps).map fun i => s!"put k{i} {String.ofList (List.replicate vlen 'a')}")
    IO.println s!"parse: {(parseRequest (toBytes line.toUTF8)).isSome}"
  | "encode" => IO.println s!"encode: {(LeanKV.Core.encodeRecord ops).size} bytes"
  | "step" => IO.println s!"step: {(LeanKV.Core.step .leaf (.batch ops)).1.toList.length}"
  | "recover" =>
    let r := LeanKV.Core.encodeRecord ops
    IO.println s!"recover: {(LeanKV.Core.recover r) matches .ok _ _ _}"
  | "manyRecords" =>
    let log := (List.range nOps).foldl (fun acc i => acc ++ LeanKV.Core.encodeRecord [.put s!"k{i}".toUTF8 (val 10)]) ByteArray.empty
    IO.println s!"recover {nOps} records: {(LeanKV.Core.recover log) matches .ok _ _ _}"
  | _ => pure ()
