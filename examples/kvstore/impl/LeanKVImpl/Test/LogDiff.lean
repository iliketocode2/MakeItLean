import LeanKVImpl.Core.Log
/-! Differential test of the core log codec against `Spec/Log.lean` (Stage 3).
Run: `lake env lean LeanKVImpl/Test/LogDiff.lean` -/
open LeanKV.Spec

def lcg (x : Nat) : Nat := (x * 1103515245 + 12345) % 2147483648
def bytesOf (seed len : Nat) : ByteArray := Id.run do
  let mut x := seed; let mut out := ByteArray.empty
  for _ in [0:len] do
    x := lcg x
    -- bias toward 0xC7 and magic bytes so stuffing paths are exercised
    let b : UInt8 := match x % 5 with | 0 => 0xC7 | 1 => 0x4B | _ => (x / 7 % 256).toUInt8
    out := out.push b
  return out

def genBatch (seed : Nat) : List (WriteOp ByteArray) :=
  (List.range (seed % 4)).map fun i =>
    if (seed + i) % 3 == 0 then .delete (bytesOf (seed * 31 + i) (1 + i))
    else .put (bytesOf (seed * 17 + i) (1 + (seed + i) % 5)) (bytesOf (seed * 13 + i) ((seed * 7 + i) % 9))

def sameRec (a : Recovery ByteArray) (b : Recovery Bytes) : Bool := a.map toBytes == b

def encOk (ops : List (WriteOp ByteArray)) : Bool :=
  toBytes (LeanKV.Core.encodeRecord ops) == encodeRecord (ops.map (WriteOp.map toBytes))

def recOk (b : ByteArray) : Bool := sameRec (LeanKV.Core.recover b) (recover (toBytes b))

def flipBit (b : ByteArray) (i bit : Nat) : ByteArray := b.set! i (b[i]! ^^^ (1 <<< bit).toUInt8)

def results :=
  -- 1. CRC table vs bitwise reference
  let crc := (List.range 200).all fun s => LeanKV.Core.crc32cBA (bytesOf s (s % 40)) == crc32c (toBytes (bytesOf s (s % 40)))
  -- 2. encoding identical to the spec, byte for byte
  let enc := (List.range 200).all fun s => encOk (genBatch s)
  -- 3. recovery on a 3-record log (one value embeds a whole record), all truncations and bit flips
  let r1 := LeanKV.Core.encodeRecord (genBatch 5)
  let r2 := LeanKV.Core.encodeRecord [.put (ByteArray.mk #[0x6B]) r1]
  let r3 := LeanKV.Core.encodeRecord (genBatch 10)
  let log := r1 ++ r2 ++ r3
  let trunc := (List.range (log.size + 1)).all fun n => recOk (log.extract 0 n)
  let flips := (List.range log.size).all fun i => (List.range 8).all fun bit => recOk (flipBit log i bit)
  -- 4. garbage between records, and random byte strings
  let garb := (List.range 50).all fun s => recOk (r1 ++ bytesOf s (1 + s % 9) ++ r3)
  let rand := (List.range 300).all fun s => recOk (bytesOf (s + 1000) (s % 60))
  (crc, enc, log.size, trunc, flips, garb, rand)

#eval results
-- Gate: every check holds.
#guard results.1 && results.2.1 && results.2.2.2.1 && results.2.2.2.2.1 && results.2.2.2.2.2.1 && results.2.2.2.2.2.2
