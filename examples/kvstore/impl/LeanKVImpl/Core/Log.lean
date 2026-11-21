import LeanKVImpl.Core.Index
import LeanKV.Spec.Log

/-!
# LeanKV core: log codec and recovery on `ByteArray` (Stage 3)

Each function mirrors the spec function of the same role in `Spec/Log.lean`, one step at a
time, but works on a `ByteArray` at an offset instead of on lists. That keeps Stage 4's proofs a
step-by-step correspondence. Two proof-licensed shortcuts:
- CRC-32C uses a 256-entry table instead of the bitwise reference;
- the corruption scan only tries offsets holding the magic's first byte 0xC7.

Intended fillings: `Impl.encodeRecord := encodeRecord`, `Impl.recover := recover`.
-/

namespace LeanKV.Core
open LeanKV.Spec

/-! ## CRC-32C -/

/-- The CRC-32C table: entry i is the spec's bitwise step applied to byte i from a zero CRC. -/
def crcTable : Array UInt32 :=
  (List.range 256).toArray.map fun i =>
    (List.range 8).foldl (fun c _ => if c &&& 1 == 1 then (c >>> 1) ^^^ 0x82F63B78 else c >>> 1)
      i.toUInt32

/-- One table-driven CRC-32C step. Equal to the spec's `crc32cByte` (a Stage 4 obligation). -/
def crcStep (crc : UInt32) (b : UInt8) : UInt32 :=
  (crc >>> 8) ^^^ crcTable[((crc ^^^ b.toUInt32) &&& 0xFF).toNat]!

/-- CRC-32C of a byte array. -/
def crc32cBA (b : ByteArray) : UInt32 :=
  (b.foldl crcStep 0xFFFFFFFF) ^^^ 0xFFFFFFFF

/-! ## Encoding -/

/-- Append a 4-byte little-endian number. -/
def pushU32 (out : ByteArray) (n : Nat) : ByteArray :=
  out |>.push (n % 256).toUInt8 |>.push (n / 256 % 256).toUInt8
    |>.push (n / 65536 % 256).toUInt8 |>.push (n / 16777216 % 256).toUInt8

/-- Append one stored write (tag, lengths, bytes). -/
def pushOp (out : ByteArray) : WriteOp ByteArray → ByteArray
  | .put k v => pushU32 (pushU32 (out.push 0x01) k.size ++ k) v.size ++ v
  | .delete k => pushU32 (out.push 0x02) k.size ++ k

/-- A batch's payload: the count, then each write. -/
def encodePayload (ops : List (WriteOp ByteArray)) : ByteArray :=
  ops.foldl pushOp (pushU32 ByteArray.empty ops.length)

/-- Append `src`, writing 0xC7 as C7 00. -/
def pushStuffed (out src : ByteArray) : ByteArray :=
  src.foldl (fun o b => if b == 0xC7 then (o.push 0xC7).push 0x00 else o.push b) out

/-- One record: magic, then the stuffed (length, payload, CRC). Intended `Impl.encodeRecord`. -/
def encodeRecord (ops : List (WriteOp ByteArray)) : ByteArray :=
  let p := encodePayload ops
  let lenAndP := pushU32 ByteArray.empty p.size ++ p
  let body := pushU32 lenAndP (crc32cBA lenAndP).toNat
  pushStuffed (ByteArray.mk #[0xC7, 0x4B, 0x56, 0x31]) body

/-! ## Decoding (mirrors `decodeRecord`) -/

/-- Read `n` original bytes from stuffed data starting at raw index `i`, appending to `acc`.
Returns the bytes and the raw bytes used. Mirrors `unstuffN`. -/
def unstuffAt (b : ByteArray) : Nat → Nat → ByteArray → Option (ByteArray × Nat)
  | 0, _, acc => some (acc, 0)
  | n + 1, i, acc =>
    if h : i < b.size then
      let x := b[i]
      if x == 0xC7 then
        if h2 : i + 1 < b.size then
          if b[i + 1] == 0x00 then
            (unstuffAt b n (i + 2) (acc.push 0xC7)).map fun (o, u) => (o, u + 2)
          else none
        else none
      else (unstuffAt b n (i + 1) (acc.push x)).map fun (o, u) => (o, u + 1)
    else none

/-- Read a 4-byte little-endian number at index `i`. Mirrors `readU32le`. -/
def readU32At (b : ByteArray) (i : Nat) : Option Nat :=
  if i + 4 ≤ b.size then
    some (b[i]!.toNat + 256 * b[i + 1]!.toNat + 65536 * b[i + 2]!.toNat + 16777216 * b[i + 3]!.toNat)
  else none

/-- Read `n` writes from payload `p` starting at index `i`. Returns the writes and the index
after them. Mirrors `decodeOps`. -/
def decodeOpsAt (p : ByteArray) : Nat → Nat → Option (List (WriteOp ByteArray) × Nat)
  | 0, i => some ([], i)
  | n + 1, i =>
    if i < p.size then
      let tag := p[i]!
      if tag == 0x01 then do
        let kl ← readU32At p (i + 1)
        let ks := i + 5
        if ks + kl ≤ p.size then
          let vl ← readU32At p (ks + kl)
          let vs := ks + kl + 4
          if vs + vl ≤ p.size then
            let (ops, j) ← decodeOpsAt p n (vs + vl)
            pure (.put (p.extract ks (ks + kl)) (p.extract vs (vs + vl)) :: ops, j)
          else none
        else none
      else if tag == 0x02 then do
        let kl ← readU32At p (i + 1)
        let ks := i + 5
        if ks + kl ≤ p.size then
          let (ops, j) ← decodeOpsAt p n (ks + kl)
          pure (.delete (p.extract ks (ks + kl)) :: ops, j)
        else none
      else none
    else none

/-- Read a whole payload; it must be exactly one batch. Mirrors `decodePayload`. -/
def decodePayloadBA (p : ByteArray) : Option (List (WriteOp ByteArray)) := do
  let n ← readU32At p 0
  let (ops, j) ← decodeOpsAt p n 4
  if j == p.size then pure ops else none

/-- Whether the magic number starts at index `i`. -/
def magicAt (b : ByteArray) (i : Nat) : Bool :=
  i + 4 ≤ b.size && b[i]! == 0xC7 && b[i + 1]! == 0x4B && b[i + 2]! == 0x56 && b[i + 3]! == 0x31

/-- Read one record starting at index `pos`: its batch and its length. Mirrors `decodeRecord`. -/
def decodeAt (b : ByteArray) (pos : Nat) : Option (List (WriteOp ByteArray) × Nat) := do
  if !magicAt b pos then none
  let (lenBytes, u1) ← unstuffAt b 4 (pos + 4) ByteArray.empty
  let len ← readU32At lenBytes 0
  let (more, u2) ← unstuffAt b (len + 4) (pos + 4 + u1) ByteArray.empty
  let payload := more.extract 0 len
  let crcBytes := more.extract len (len + 4)
  if crcBytes.toList == u32le (crc32cBA (lenBytes ++ payload)).toNat then
    let ops ← decodePayloadBA payload
    if batchValid ops then pure (ops, 4 + u1 + u2) else none
  else none

/-! ## Recovery (mirrors `recover`) -/

/-- Read valid records from index `pos` while possible (at most `fuel` of them). Returns their
batches and the index where reading stopped. Mirrors `readRecords`. -/
def readFrom (b : ByteArray) : Nat → Nat → List (List (WriteOp ByteArray)) × Nat
  | 0, pos => ([], pos)
  | fuel + 1, pos =>
    match decodeAt b pos with
    | some (ops, n) =>
      if 0 < n ∧ pos + n ≤ b.size then
        let (rs, stop) := readFrom b fuel (pos + n)
        (ops :: rs, stop)
      else ([], pos)
    | none => ([], pos)

/-- Whether a valid record starts anywhere after `p`. Only offsets holding 0xC7 can start one. -/
def validAfter (b : ByteArray) (p : Nat) : Bool :=
  (List.range' (p + 1) (b.size - (p + 1))).any fun q => b[q]! == 0xC7 && (decodeAt b q).isSome

/-- Recovery on a `ByteArray` log. Intended `Impl.recover`. -/
def recover (b : ByteArray) : Recovery ByteArray :=
  let (recs, p) := readFrom b (b.size + 1) 0
  if validAfter b p then .corrupt p else .ok recs p (b.size - p)

end LeanKV.Core
