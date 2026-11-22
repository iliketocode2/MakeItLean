import LeanKVImpl.Core.Store
import LeanKVSol.Base.Wire

/-! In-process component profile (Stage 7): where does LeanKV spend CPU time? -/

namespace LeanKV.Shell
open LeanKV.Spec

def key (i : Nat) : ByteArray := s!"user{toString (1000000000000 + i) |>.drop 1}".toUTF8
def val (i : Nat) : ByteArray := ⟨(List.range 100).toArray.map fun j => ((i + j) % 251).toUInt8⟩

def timeIt (name : String) (reps : Nat) (f : Nat → IO Unit) : IO Unit := do
  let t0 ← IO.monoNanosNow
  for i in [0:reps] do f i
  let t1 ← IO.monoNanosNow
  IO.println s!"  {name}: {(t1 - t0) / reps} ns per op ({reps} reps)"

def main : IO Unit := do
  let batch : List (WriteOp ByteArray) := (List.range 100).map fun i => .put (key i) (val i)
  let rec10k := Core.encodeRecord batch
  IO.println s!"record for a 100-put batch: {rec10k.size} bytes"
  timeIt "encodeRecord (100 puts, direct ByteArray)" 200 fun i => do
    let r := Core.encodeRecord ((List.range 100).map fun j => .put (key (i + j)) (val i)); if r.size == 0 then IO.println "?"
  timeIt "crc32c of 12 KB (unrolled bitwise)" 200 fun _ => do
    let c := Core.crc32cBA rec10k; if c == 0 then IO.println "?"
  timeIt "decodeAt (one 10 KB record)" 200 fun _ => do
    if (Core.decodeAt rec10k 0).isNone then IO.println "?"
  -- a 5 MB log of 500 such records
  let log := (List.range 500).foldl (fun acc b =>
    acc ++ Core.encodeRecord ((List.range 100).map fun i => .put (key (b * 100 + i)) (val i))) ByteArray.empty
  timeIt s!"recover ({log.size / 1024} KB, 500 records)" 3 fun _ => do
    if Core.recover log matches .corrupt _ then IO.println "?"
  -- index operations on 50k keys
  let t := (List.range 50000).foldl (fun t i => Core.insert t (key i) (val i)) Tree.leaf
  timeIt "Core.step get (50k keys)" 20000 fun i => do
    let (_, r) := Core.step t (.get (key (i * 7 % 50000))); if r matches .notFound then IO.println "?"
  timeIt "Core.step scan 10 (50k keys)" 20000 fun i => do
    let (_, r) := Core.step t (.scan (key (i * 7 % 50000)) .unbounded 10); if r matches .notFound then IO.println "?"
  timeIt "Core.step put (50k keys)" 20000 fun i => do
    let (t', _) := Core.step t (.put (key (i * 13 % 60000)) (val i)); if Core.ht t' == 0 then IO.println "?"
  let line := toBytes s!"put {String.ofList ((toBytes (key 5)).map (Char.ofNat ·.toNat))} {String.ofList (List.replicate 100 'a')}".toUTF8
  timeIt "parseRequest (put, 100 B value, via lists)" 20000 fun _ => do
    if (parseRequest line).isNone then IO.println "?"
  let batchLine := toBytes ("batch " ++ " ".intercalate ((List.range 100).map fun i => s!"put k{i} {String.ofList (List.replicate 100 'a')}")).toUTF8
  timeIt "parseRequest (batch of 100)" 200 fun _ => do
    if (parseRequest batchLine).isNone then IO.println "?"

end LeanKV.Shell

def main : IO Unit := LeanKV.Shell.main
