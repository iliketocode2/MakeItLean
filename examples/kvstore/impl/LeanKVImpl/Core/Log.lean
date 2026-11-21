import LeanKVImpl.Core.Index
import LeanKV.Spec.Log

/-!
# LeanKV core: log codec and recovery on `ByteArray` (Stage 3)

Each function mirrors the spec function of the same role in `Spec/Log.lean`, one step at a
time, but works on a `ByteArray` at an offset instead of on lists. That keeps Stage 4's proofs a
step-by-step correspondence. One proof-licensed shortcut: the corruption scan only tries offsets holding the magic's first
byte 0xC7.

Intended fillings: `Impl.encodeRecord := encodeRecord`, `Impl.recover := recover`.
-/

namespace LeanKV.Core
open LeanKV.Spec

/-! ## CRC-32C and encoding

v1 uses the spec's bitwise CRC-32C and the spec's encoder directly, so their correctness
obligations are immediate. A table-driven CRC and a direct `ByteArray` encoder are Stage 7
optimizations, each needing a proof (`bv_decide` is not usable: it relies on the
`Lean.ofReduceBool` axiom, which the comparator's axiom whitelist rejects).
-/

/-- CRC-32C of a byte array (the spec's bitwise definition). -/
def crc32cBA (b : ByteArray) : UInt32 := crc32c (toBytes b)

/-- One record, in exactly the spec's format. Intended `Impl.encodeRecord`. -/
def encodeRecord (ops : List (WriteOp ByteArray)) : ByteArray :=
  ofBytes (Spec.encodeRecord (ops.map (WriteOp.map toBytes)))

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
