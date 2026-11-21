import LeanKV.Spec.Model

/-!
# LeanKV spec: log format and recovery (R8, R11, R12)

The log is a byte sequence of records, one per acknowledged write (a batch; `put` and
`delete` are one-op batches). This file fixes the record format and defines `recover`, the
reference meaning of reading a log back. That includes the R12 rule: a bad record at the
tail is ignored, and a bad record followed by a valid one is corruption.

Record format:

    record = magic ++ stuff (u32le len ++ payload ++ u32le (crc32c (u32le len ++ payload)))

**Why stuffing.** Inside the stuffed part, the magic's first byte 0xC7 is always written as
`C7 00`. So the 4-byte magic `C7 4B 56 31` can only appear at the start of a record. Without
this, a stored value whose bytes contain a complete valid record (for example, a backup of
another LeanKV log) could make a torn write look like "a valid record after a bad one", and
the store would wrongly refuse to open. With stuffing, `recover_torn_tail` holds for every
possible stored value. Cost: about 0.4% size overhead on random data, at most 2× in the worst
case.

**Strength (R12).** For random bytes to pass as a record they must match the 32-bit magic and
the 32-bit CRC: a chance of about 2⁻⁶⁴ per offset, within the required 2⁻⁶⁰. This is a
probabilistic design argument, not a theorem.
-/

namespace LeanKV.Spec

/-! ## Checksum and integers -/

/-- English: One step of CRC-32C (Castagnoli, reflected polynomial 0x82F63B78) over one byte,
bit by bit. This is the simple, slow reference. An implementation may use a table-driven or
hardware version proven equal to it. -/
def crc32cByte (crc : UInt32) (b : UInt8) : UInt32 :=
  (List.range 8).foldl
    (fun c _ => if c &&& 1 == 1 then (c >>> 1) ^^^ 0x82F63B78 else c >>> 1)
    (crc ^^^ b.toUInt32)

/-- English: The CRC-32C checksum of a byte string (initial value and final XOR 0xFFFFFFFF).
Standard check value: the checksum of the ASCII text "123456789" is 0xE3069283. -/
def crc32c (bs : Bytes) : UInt32 := (bs.foldl crc32cByte 0xFFFFFFFF) ^^^ 0xFFFFFFFF

/-- English: A number below 2³² written as 4 bytes, least significant first. -/
def u32le (n : Nat) : Bytes :=
  [(n % 256).toUInt8, (n / 256 % 256).toUInt8, (n / 65536 % 256).toUInt8,
    (n / 16777216 % 256).toUInt8]

/-- English: Read a 4-byte little-endian number from the front of a byte string, returning
the number and the remaining bytes. -/
def readU32le : Bytes → Option (Nat × Bytes)
  | a :: b :: c :: d :: rest =>
    some (a.toNat + 256 * b.toNat + 65536 * c.toNat + 16777216 * d.toNat, rest)
  | _ => none

/-- English: Split off exactly the first `n` bytes, failing if there are fewer. -/
def takeExact (n : Nat) (b : Bytes) : Option (Bytes × Bytes) :=
  if n ≤ b.length then some (b.take n, b.drop n) else none

/-! ## Batch payload -/

/-- English: How one write is stored: tag 1, key length, key, value length, value for a put;
tag 2, key length, key for a delete. -/
def encodeOp : WriteOp Bytes → Bytes
  | .put k v => 0x01 :: (u32le k.length ++ k ++ u32le v.length ++ v)
  | .delete k => 0x02 :: (u32le k.length ++ k)

/-- English: How a batch is stored: the number of writes, then each write in order. -/
def encodePayload (ops : List (WriteOp Bytes)) : Bytes :=
  u32le ops.length ++ ops.flatMap encodeOp

/-- English: Read `n` writes from the front of a byte string, returning them and the
remaining bytes. -/
def decodeOps : Nat → Bytes → Option (List (WriteOp Bytes) × Bytes)
  | 0, b => some ([], b)
  | n + 1, 0x01 :: b => do
    let (klen, b) ← readU32le b
    let (k, b) ← takeExact klen b
    let (vlen, b) ← readU32le b
    let (v, b) ← takeExact vlen b
    let (ops, b) ← decodeOps n b
    pure (.put k v :: ops, b)
  | n + 1, 0x02 :: b => do
    let (klen, b) ← readU32le b
    let (k, b) ← takeExact klen b
    let (ops, b) ← decodeOps n b
    pure (.delete k :: ops, b)
  | _ + 1, _ => none

/-- English: Read a stored batch. The bytes must be exactly one encoded batch, with nothing
left over. -/
def decodePayload (p : Bytes) : Option (List (WriteOp Bytes)) := do
  let (n, b) ← readU32le p
  let (ops, rest) ← decodeOps n b
  if rest.isEmpty then pure ops else none

/-! ## Framing and stuffing -/

/-- English: The 4-byte magic number that starts every record: C7 4B 56 31. Its bytes are all
different, and its first byte 0xC7 does not occur in the other three. -/
def magic : Bytes := [0xC7, 0x4B, 0x56, 0x31]

/-- English: Stuff one byte: 0xC7 is written as C7 00; every other byte as itself. -/
def stuffByte (b : UInt8) : Bytes := if b == 0xC7 then [0xC7, 0x00] else [b]

/-- English: Stuff a byte string, so that it never contains the magic number. -/
def stuff (b : Bytes) : Bytes := b.flatMap stuffByte

/-- English: Read `n` original bytes from the front of a stuffed byte string, returning them
and how many stuffed bytes were used. Fails if the input runs out or 0xC7 is not followed by
00. -/
def unstuffN : Nat → Bytes → Option (Bytes × Nat)
  | 0, _ => some ([], 0)
  | n + 1, 0xC7 :: 0x00 :: rest => do
    let (out, used) ← unstuffN n rest
    pure (0xC7 :: out, used + 2)
  | _ + 1, 0xC7 :: _ => none
  | n + 1, b :: rest => do
    let (out, used) ← unstuffN n rest
    pure (b :: out, used + 1)
  | _ + 1, [] => none

/-- English: The part of a record after the magic, before stuffing: payload length, payload,
and the CRC-32C of length and payload together. -/
def recordBody (ops : List (WriteOp Bytes)) : Bytes :=
  let p := encodePayload ops
  u32le p.length ++ p ++ u32le (crc32c (u32le p.length ++ p)).toNat

/-- English: How one acknowledged write (a batch) is stored in the log: the magic, then the
stuffed body. -/
def encodeRecord (ops : List (WriteOp Bytes)) : Bytes := magic ++ stuff (recordBody ops)

/-- English: A log holding the given batches, one record each, in order. -/
def encodeLog (bs : List (List (WriteOp Bytes))) : Bytes := bs.flatMap encodeRecord

/-- English: Read one record from the front of a byte string, returning its batch and its
length in bytes. A record is valid only if the magic matches, the body unstuffs, the checksum
matches, the payload is exactly one batch, and that batch is within the limits (R8a). -/
def decodeRecord (b : Bytes) : Option (List (WriteOp Bytes) × Nat) := do
  let rest ← if magic.isPrefixOf b then some (b.drop magic.length) else none
  let (lenBytes, used1) ← unstuffN 4 rest
  let (len, _) ← readU32le lenBytes
  let (more, used2) ← unstuffN (len + 4) (rest.drop used1)
  let payload := more.take len
  if more.drop len == u32le (crc32c (lenBytes ++ payload)).toNat then
    let ops ← decodePayload payload
    if validBatch ops then pure (ops, magic.length + used1 + used2) else none
  else none

/-! ## Recovery -/

/-- English: Read valid records from the start of the log for as long as possible. Returns
their batches and the offset where reading stopped (the end of the log, or the start of the
first bad record). -/
def readRecords (b : Bytes) : List (List (WriteOp Bytes)) × Nat :=
  match decodeRecord b with
  | some (ops, n) =>
    if h : 0 < n ∧ n ≤ b.length then
      let r := readRecords (b.drop n)
      (ops :: r.1, n + r.2)
    else ([], 0)
  | none => ([], 0)
termination_by b.length
decreasing_by simp only [List.length_drop]; omega

/-- English: Whether a valid record starts at byte offset `q` of the log. -/
def validRecordAt (b : Bytes) (q : Nat) : Bool := (decodeRecord (b.drop q)).isSome

/-- English: The outcome of recovery (R12). -/
inductive Recovery (β : Type) where
  /-- English: The store opens with these batches, read from the first `validLen` bytes. The
  last `tailIgnored` bytes are a torn tail and are ignored (and truncated before new
  writes). -/
  | ok (batches : List (List (WriteOp β))) (validLen tailIgnored : Nat)
  /-- English: The store refuses to open: the record at byte offset `offset` is bad, but a
  valid record follows it. -/
  | corrupt (offset : Nat)
  deriving Repr, DecidableEq

/-- English: Change the byte-string representation inside a recovery outcome. -/
def Recovery.map {β γ : Type} (f : β → γ) : Recovery β → Recovery γ
  | .ok bs n t => .ok (bs.map (·.map (WriteOp.map f))) n t
  | .corrupt p => .corrupt p

/-- English: The reference meaning of reading a log back (R11, R12). Read valid records from
the start until the first bad one, at offset p. If a valid record starts at any later offset,
the log is corrupt at p. Otherwise everything from p on is a torn tail, and the store opens
with the records before p. -/
def recover (b : Bytes) : Recovery Bytes :=
  let (recs, p) := readRecords b
  if (List.range b.length).any (fun q => p < q && validRecordAt b q) then .corrupt p
  else .ok recs p (b.length - p)

/-- English: The store contents after a successful recovery: the recovered batches applied
in order to the empty store. -/
def Recovery.state? : Recovery Bytes → Option Store
  | .ok bs _ _ => some (bs.foldl (fun s ops => ops.foldl WriteOp.apply s) Store.empty)
  | .corrupt _ => none

/-! ## Implementation holes -/

/-- English: IMPLEMENTATION HOLE. The bytes the implementation appends to the log for one
acknowledged batch, working on `ByteArray`s. -/
def Impl.encodeRecord : List (WriteOp ByteArray) → ByteArray := sorry

/-- English: IMPLEMENTATION HOLE. The implementation's recovery, working on `ByteArray`s (it
may, for example, search only for magic positions instead of trying every offset). -/
def Impl.recover : ByteArray → Recovery ByteArray := sorry

/-- English: The implementation writes records in exactly the spec's format. -/
theorem impl_encodeRecord_eq (ops : List (WriteOp ByteArray)) :
    toBytes (Impl.encodeRecord ops) = encodeRecord (ops.map (WriteOp.map toBytes)) := sorry

/-- English: The implementation's recovery gives exactly the reference outcome, for every
possible log content (R11, R12). -/
theorem impl_recover_eq (b : ByteArray) :
    (Impl.recover b).map toBytes = recover (toBytes b) := sorry

/-! ## Required properties of the format (proven in Stage 2) -/

/-- English: The checksum is standard CRC-32C: the checksum of the ASCII text "123456789" is
0xE3069283. -/
theorem crc32c_check_value :
    crc32c [0x31, 0x32, 0x33, 0x34, 0x35, 0x36, 0x37, 0x38, 0x39] = 0xE3069283 := sorry

/-- English: A record decodes back to its batch and its exact length, whatever bytes follow
it. -/
theorem decodeRecord_encodeRecord {ops : List (WriteOp Bytes)} (h : validBatch ops = true)
    (rest : Bytes) :
    decodeRecord (encodeRecord ops ++ rest) = some (ops, (encodeRecord ops).length) := sorry

/-- English: The magic number appears in a record only at its start. It never appears at any
later offset, even running into whatever bytes follow the record. -/
theorem magic_only_at_start (ops : List (WriteOp Bytes)) (rest : Bytes) {i : Nat}
    (hi0 : 0 < i) (hi : i < (encodeRecord ops).length) :
    ¬ magic.IsPrefix ((encodeRecord ops ++ rest).drop i) := sorry

/-- English: A log of valid records recovers to exactly those batches, with no tail
(R10). -/
theorem recover_encodeLog {bs : List (List (WriteOp Bytes))}
    (h : ∀ ops ∈ bs, validBatch ops = true) :
    recover (encodeLog bs) = .ok bs (encodeLog bs).length 0 := sorry

/-- English: Torn tail (R11, R12). If a crash leaves only part of the next record, recovery
opens with exactly the earlier records and ignores the partial one. This holds whatever the
stored keys and values are. -/
theorem recover_torn_tail {bs : List (List (WriteOp Bytes))}
    (h : ∀ ops ∈ bs, validBatch ops = true) {ops : List (WriteOp Bytes)}
    (hops : validBatch ops = true) {t : Bytes} (ht : t.IsPrefix (encodeRecord ops))
    (hlt : t.length < (encodeRecord ops).length) :
    recover (encodeLog bs ++ t) = .ok bs (encodeLog bs).length t.length := sorry

/-- English: Corruption (R12). If a bad record sits between valid records, recovery refuses
and reports the bad record's offset. -/
theorem recover_corrupt {bs cs : List (List (WriteOp Bytes))}
    (hbs : ∀ ops ∈ bs, validBatch ops = true) (hcs : ∀ ops ∈ cs, validBatch ops = true)
    (hne : cs ≠ []) {g : Bytes} (hg : decodeRecord (g ++ encodeLog cs) = none) :
    recover (encodeLog bs ++ g ++ encodeLog cs) = .corrupt (encodeLog bs).length := sorry

/-- English: Truncating a torn tail and appending a new record recovers the earlier records
plus the new one. This is why the store must truncate before writing (R12). -/
theorem recover_after_truncate {bs : List (List (WriteOp Bytes))}
    (h : ∀ ops ∈ bs, validBatch ops = true) {ops : List (WriteOp Bytes)}
    (hops : validBatch ops = true) :
    recover (encodeLog bs ++ encodeRecord ops) =
      .ok (bs ++ [ops]) (encodeLog bs ++ encodeRecord ops).length 0 := sorry

end LeanKV.Spec
