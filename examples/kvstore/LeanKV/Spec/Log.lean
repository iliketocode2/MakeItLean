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
    if _h : 0 < n ∧ n ≤ b.length then
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

/-! ## Required properties of the format and their proofs (Stage 2) -/

set_option maxRecDepth 10000 in
/-- English: The checksum is standard CRC-32C: the checksum of the ASCII text "123456789" is
0xE3069283. -/
theorem crc32c_check_value :
    crc32c [0x31, 0x32, 0x33, 0x34, 0x35, 0x36, 0x37, 0x38, 0x39] = 0xE3069283 := by rfl

/-- English: A 4-byte number is 4 bytes long. -/
theorem u32le_length (n : Nat) : (u32le n).length = 4 := rfl

/-- English: Reading back a written 4-byte number (below 2³²) gives the number and whatever followed it. -/
theorem readU32le_u32le {n : Nat} (h : n < 2 ^ 32) (r : Bytes) : readU32le (u32le n ++ r) = some (n, r) := by
  simp only [u32le, List.cons_append, List.nil_append, readU32le, Option.some.injEq, Prod.mk.injEq, and_true]
  simp [UInt8.toNat_ofNat']
  omega

/-- English: Splitting off exactly as many bytes as x has, from x followed by r, gives x and r. -/
theorem takeExact_append (x r : Bytes) : takeExact x.length (x ++ r) = some (x, r) := by
  simp [takeExact]

/-- English: A valid write's key and value are each shorter than 2³² bytes, so their lengths fit in 4 bytes. -/
theorem writeOp_valid_lens {op : WriteOp Bytes} (h : op.valid = true) :
    match op with
    | .put k v => k.length < 2 ^ 32 ∧ v.length < 2 ^ 32
    | .delete k => k.length < 2 ^ 32 := by
  cases op <;> simp only [WriteOp.valid, validKey, validValue, Bool.and_eq_true, decide_eq_true_eq] at h <;>
    simp only [maxKeyLen, maxValueLen] at h <;> simp only <;> omega

/-- English: Reading back a list of valid stored writes gives the writes and whatever followed them. -/
theorem decodeOps_flatMap (ops : List (WriteOp Bytes)) (hops : ∀ op ∈ ops, op.valid = true) (r : Bytes) :
    decodeOps ops.length (ops.flatMap encodeOp ++ r) = some (ops, r) := by
  induction ops with
  | nil => rfl
  | cons op ops ih =>
    have ih' := ih (fun o ho => hops o (List.mem_cons_of_mem _ ho))
    have hv := writeOp_valid_lens (hops op (by simp))
    cases op with
    | put k v =>
      simp only [List.length_cons, List.flatMap_cons, encodeOp, List.cons_append, List.append_assoc]
      simp [decodeOps, readU32le_u32le hv.1, readU32le_u32le hv.2, takeExact_append, ih']
    | delete k =>
      simp only [List.length_cons, List.flatMap_cons, encodeOp, List.cons_append, List.append_assoc]
      simp [decodeOps, readU32le_u32le hv, takeExact_append, ih']

/-- English: A stored write takes at most 9 bytes plus its key and value bytes. -/
theorem encodeOp_length_le (op : WriteOp Bytes) : (encodeOp op).length ≤ 9 + op.size := by
  cases op <;> simp [encodeOp, WriteOp.size, u32le_length] <;> omega

/-- English: Stored writes take at most 9 bytes each plus their key and value bytes. -/
theorem flatMap_encodeOp_length_le (ops : List (WriteOp Bytes)) :
    (ops.flatMap encodeOp).length ≤ 9 * ops.length + (ops.map WriteOp.size).sum := by
  induction ops with
  | nil => simp
  | cons op ops ih =>
    simp only [List.flatMap_cons, List.length_append, List.length_cons, List.map_cons, List.sum_cons]
    have := encodeOp_length_le op; omega

/-- English: A valid batch's stored payload is shorter than 2³² bytes, so its length fits in 4 bytes. -/
theorem encodePayload_length_lt {ops : List (WriteOp Bytes)} (h : validBatch ops = true) :
    (encodePayload ops).length < 2 ^ 32 := by
  simp only [validBatch, Bool.and_eq_true, decide_eq_true_eq] at h
  simp only [maxBatchOps, maxBatchBytes] at h
  have := flatMap_encodeOp_length_le ops
  simp only [encodePayload, List.length_append, u32le_length]; omega

/-- English: Reading back a valid stored batch gives the batch. -/
theorem decodePayload_encodePayload {ops : List (WriteOp Bytes)} (h : validBatch ops = true) :
    decodePayload (encodePayload ops) = some ops := by
  have hall : ∀ op ∈ ops, op.valid = true := by
    simp only [validBatch, Bool.and_eq_true, List.all_eq_true] at h; exact h.1.2
  have hlen : ops.length < 2 ^ 32 := by
    simp only [validBatch, Bool.and_eq_true, decide_eq_true_eq] at h
    simp only [maxBatchOps] at h; omega
  have := decodeOps_flatMap ops hall []
  simp only [List.append_nil] at this
  simp [decodePayload, encodePayload, readU32le_u32le hlen, this]

/-! stuffing -/

/-- English: Stuffing two byte strings one after the other is the same as stuffing them separately. -/
theorem stuff_append (x y : Bytes) : stuff (x ++ y) = stuff x ++ stuff y := by
  simp [stuff, List.flatMap_append]

/-- English: Unstuffing as many bytes as x has, from stuffed x followed by anything, gives x and the stuffed length. -/
theorem unstuffN_stuff : ∀ (x r : Bytes), unstuffN x.length (stuff x ++ r) = some (x, (stuff x).length)
  | [], r => by simp [unstuffN, stuff]
  | b :: x, r => by
    have ih := unstuffN_stuff x r
    by_cases hb : b = 0xC7
    · subst hb
      simp only [stuff, List.flatMap_cons, stuffByte, beq_self_eq_true, ↓reduceIte, List.length_cons,
        List.cons_append, List.nil_append] at ih ⊢
      rw [unstuffN]

      rw [ih]; simp
    · have hb' : (b == 0xC7) = false := by simpa using hb
      simp only [stuff, List.flatMap_cons, stuffByte, hb', Bool.false_eq_true, ↓reduceIte,
        List.length_cons, List.cons_append, List.nil_append] at ih ⊢
      rw [unstuffN]
      · rw [ih]; simp
      all_goals (intros; simp_all)

/-- English: Unstuffing as many bytes as x has, from stuffed (x then y) followed by anything, gives x. -/
theorem unstuffN_stuff_append (x y r : Bytes) :
    unstuffN x.length (stuff (x ++ y) ++ r) = some (x, (stuff x).length) := by
  rw [stuff_append, List.append_assoc]; exact unstuffN_stuff x _

/-- English: A byte string is a prefix of itself followed by anything. -/
theorem isPrefixOf_append_self (p x : Bytes) : p.isPrefixOf (p ++ x) = true := by
  induction p with
  | nil => rfl
  | cons a p ih => simp [ih]

/-- English: A record decodes back to its batch and its exact length, whatever bytes follow
it. -/
theorem decodeRecord_encodeRecord {ops : List (WriteOp Bytes)} (h : validBatch ops = true)
    (rest : Bytes) :
    decodeRecord (encodeRecord ops ++ rest) = some (ops, (encodeRecord ops).length) := by
  have hL := encodePayload_length_lt h
  generalize hp : encodePayload ops = p at hL
  have hdec : decodePayload p = some ops := hp ▸ decodePayload_encodePayload h
  have e1 : encodeRecord ops ++ rest =
      magic ++ (stuff (u32le p.length ++ (p ++ u32le (crc32c (u32le p.length ++ p)).toNat)) ++ rest) := by
    simp [encodeRecord, recordBody, hp]
  have h4 : unstuffN 4 (stuff (u32le p.length ++ (p ++ u32le (crc32c (u32le p.length ++ p)).toNat)) ++ rest)
      = some (u32le p.length, (stuff (u32le p.length)).length) :=
    unstuffN_stuff_append (u32le p.length) _ rest
  have hlen : (p ++ u32le (crc32c (u32le p.length ++ p)).toNat).length = p.length + 4 := by
    simp [u32le_length]
  have h5 := unstuffN_stuff (p ++ u32le (crc32c (u32le p.length ++ p)).toNat) rest
  rw [hlen] at h5
  have hr : readU32le (u32le p.length) = some (p.length, []) := by
    have := readU32le_u32le hL []; simpa using this
  rw [e1]
  simp only [decodeRecord, isPrefixOf_append_self, ↓reduceIte, List.drop_left' (rfl : magic.length = 4)]
  simp only [bind, Option.bind]
  rw [h4]; simp only [hr]
  rw [stuff_append, List.append_assoc, List.drop_left, h5]
  simp [hdec, h, stuff_append, encodeRecord, recordBody, hp, magic]
  omega

/-- English: Every record is at least 4 bytes long (its magic number). -/
theorem encodeRecord_length_pos (ops : List (WriteOp Bytes)) : 4 ≤ (encodeRecord ops).length := by
  simp [encodeRecord, magic]

/-- English: An empty byte string is not a record. -/
theorem decodeRecord_nil : decodeRecord [] = none := by decide

/-- English: Reading records from an empty log gives no records. -/
theorem readRecords_nil : readRecords [] = ([], 0) := by
  rw [readRecords, decodeRecord_nil]

/-- English: Reading records from a valid record followed by r gives that record, then whatever is read from r. -/
theorem readRecords_cons {ops : List (WriteOp Bytes)} (h : validBatch ops = true) (r : Bytes) :
    readRecords (encodeRecord ops ++ r) =
      (ops :: (readRecords r).1, (encodeRecord ops).length + (readRecords r).2) := by
  rw [readRecords, decodeRecord_encodeRecord h]
  have h4 := encodeRecord_length_pos ops
  simp only [List.length_append]
  have hc : 0 < (encodeRecord ops).length ∧
      (encodeRecord ops).length ≤ (encodeRecord ops).length + r.length := ⟨by omega, by omega⟩
  simp only [hc]
  simp

/-- English: The log of a batch followed by more batches is that batch's record followed by their log. -/
theorem encodeLog_cons (ops : List (WriteOp Bytes)) (bs : List (List (WriteOp Bytes))) :
    encodeLog (ops :: bs) = encodeRecord ops ++ encodeLog bs := by simp [encodeLog]

/-- English: Reading records from a log of valid records followed by r gives those records, then whatever is read from r. -/
theorem readRecords_encodeLog {bs : List (List (WriteOp Bytes))} (h : ∀ ops ∈ bs, validBatch ops = true)
    (r : Bytes) :
    readRecords (encodeLog bs ++ r) = (bs ++ (readRecords r).1, (encodeLog bs).length + (readRecords r).2) := by
  induction bs with
  | nil => simp [encodeLog]
  | cons ops bs ih =>
    rw [encodeLog_cons, List.append_assoc, readRecords_cons (h ops (by simp)),
      ih (fun o ho => h o (List.mem_cons_of_mem _ ho))]
    simp; omega

/-- English: A log of valid records recovers to exactly those batches, with no tail
(R10). -/
theorem recover_encodeLog {bs : List (List (WriteOp Bytes))}
    (h : ∀ ops ∈ bs, validBatch ops = true) :
    recover (encodeLog bs) = .ok bs (encodeLog bs).length 0 := by
  have := readRecords_encodeLog h []
  simp only [List.append_nil, readRecords_nil, Nat.add_zero] at this
  unfold recover
  rw [this]
  simp only
  have : ((List.range (encodeLog bs).length).any
      (fun q => decide ((encodeLog bs).length < q) && validRecordAt (encodeLog bs) q)) = false := by
    rw [List.any_eq_false]; intro q hq; simp at hq; simp; omega
  rw [this]; simp

/-- English: Truncating a torn tail and appending a new record recovers the earlier records
plus the new one. This is why the store must truncate before writing (R12). -/
theorem recover_after_truncate {bs : List (List (WriteOp Bytes))}
    (h : ∀ ops ∈ bs, validBatch ops = true) {ops : List (WriteOp Bytes)}
    (hops : validBatch ops = true) :
    recover (encodeLog bs ++ encodeRecord ops) =
      .ok (bs ++ [ops]) (encodeLog bs ++ encodeRecord ops).length 0 := by
  have e : encodeLog bs ++ encodeRecord ops = encodeLog (bs ++ [ops]) := by simp [encodeLog]
  rw [e]
  apply recover_encodeLog
  intro o ho; simp at ho; rcases ho with ho | rfl
  · exact h o ho
  · exact hops

/-- English: Stuffing a byte followed by more bytes stuffs the byte, then the rest. -/
theorem stuff_cons (b : UInt8) (x : Bytes) : stuff (b :: x) = stuffByte b ++ stuff x := by
  simp [stuff]

/-- English: In a stuffed byte string, every 0xC7 is immediately followed by 0x00. -/
theorem stuff_C7_then_00 : ∀ (x : Bytes) (j : Nat), (stuff x)[j]? = some 0xC7 → (stuff x)[j + 1]? = some 0x00
  | [], j, h => by simp [stuff] at h
  | b :: x, j, h => by
    rw [stuff_cons] at h ⊢
    by_cases hb : b = 0xC7
    · subst hb
      have e : stuffByte 0xC7 = [0xC7, 0x00] := by decide
      rw [e] at h ⊢
      match j, h with
      | 0, _ => simp
      | 1, h => simp at h
      | j + 2, h =>
        simp only [List.cons_append, List.nil_append, List.getElem?_cons_succ] at h ⊢
        exact stuff_C7_then_00 x j h
    · have e : stuffByte b = [b] := by simp [stuffByte, hb]
      rw [e] at h ⊢
      match j, h with
      | 0, h => simp at h; exact absurd h hb
      | j + 1, h =>
        simp only [List.cons_append, List.nil_append, List.getElem?_cons_succ] at h ⊢
        exact stuff_C7_then_00 x j h

/-- English: A byte string that starts with the magic number has 0xC7 first and 0x4B second. -/
theorem magic_prefix_getElem {l : Bytes} (h : magic.IsPrefix l) :
    l[0]? = some 0xC7 ∧ l[1]? = some 0x4B := by
  obtain ⟨t, rfl⟩ := h
  simp [magic]

/-- English: The magic number appears in a record only at its start. It never appears at any
later offset, even running into whatever bytes follow the record. -/
theorem magic_only_at_start (ops : List (WriteOp Bytes)) (rest : Bytes) {i : Nat}
    (hi0 : 0 < i) (hi : i < (encodeRecord ops).length) :
    ¬ magic.IsPrefix ((encodeRecord ops ++ rest).drop i) := by
  intro hm
  obtain ⟨h0, h1⟩ := magic_prefix_getElem hm
  simp only [List.getElem?_drop, Nat.add_zero] at h0 h1
  generalize hB : stuff (recordBody ops) = B at hi
  have hl : encodeRecord ops ++ rest = magic ++ (B ++ rest) := by
    simp [encodeRecord, hB]
  rw [hl] at h0 h1
  have hlen : (encodeRecord ops).length = 4 + B.length := by simp [encodeRecord, hB, magic]; omega
  rw [hlen] at hi
  by_cases hi4 : i < 4
  · have : i = 1 ∨ i = 2 ∨ i = 3 := by omega
    rcases this with rfl | rfl | rfl <;> simp [magic] at h0
  · have hm4 : magic.length = 4 := rfl
    rw [List.getElem?_append_right (by omega), hm4] at h0 h1
    have hj : i - 4 < B.length := by omega
    rw [List.getElem?_append_left hj] at h0
    have hnext := stuff_C7_then_00 (recordBody ops) (i - 4) (hB ▸ h0)
    rw [hB] at hnext
    have hj1 : i + 1 - 4 = i - 4 + 1 := by omega
    rw [hj1] at h1
    have hlt : i - 4 + 1 < B.length := by
      have := (List.getElem?_eq_some_iff.mp hnext).1; exact this
    rw [List.getElem?_append_left hlt, hnext] at h1
    simp at h1

/-- English: Unstuffing never reads past what it uses: if it succeeds on x, it uses at most x's bytes and gives the same result whatever follows x. -/
theorem unstuffN_append : ∀ (n : Nat) (x : Bytes) {o : Bytes} {u : Nat}, unstuffN n x = some (o, u) →
    u ≤ x.length ∧ ∀ v, unstuffN n (x ++ v) = some (o, u)
  | 0, x, o, u, h => by
    simp [unstuffN] at h; obtain ⟨rfl, rfl⟩ := h; simp [unstuffN]
  | n + 1, [], _, _, h => by simp [unstuffN] at h
  | n + 1, b :: x, o, u, h => by
    by_cases hb : b = 0xC7
    · subst hb
      cases x with
      | nil => simp [unstuffN] at h
      | cons c x =>
        by_cases hc : c = 0x00
        · subst hc
          simp only [unstuffN, bind, Option.bind] at h
          split at h
          · simp at h
          · rename_i p hp
            simp at h; obtain ⟨rfl, rfl⟩ := h
            obtain ⟨hle, hv⟩ := unstuffN_append n x hp
            refine ⟨by simp; omega, fun v => ?_⟩
            simp only [List.cons_append, unstuffN, bind, Option.bind, hv]; rfl
        · have : unstuffN (n + 1) (0xC7 :: c :: x) = none := by
            rw [unstuffN]; all_goals (intros; simp_all)
          rw [this] at h; simp at h
    · have e : ∀ y, unstuffN (n + 1) (b :: y) = (unstuffN n y).bind (fun p => some (b :: p.1, p.2 + 1)) := by
        intro y; rw [unstuffN]
        · rfl
        all_goals (intros; simp_all)
      rw [e] at h
      cases hp : unstuffN n x with
      | none => rw [hp] at h; simp at h
      | some p =>
        rw [hp] at h; simp at h; obtain ⟨rfl, rfl⟩ := h
        obtain ⟨hle, hv⟩ := unstuffN_append n x hp
        refine ⟨by simp; omega, fun v => ?_⟩
        rw [List.cons_append, e, hv]; rfl

/-- English: If p is a prefix of t, it is a prefix of t followed by anything, and is no longer than t. -/
theorem isPrefixOf_append_of {p t : Bytes} (h : p.isPrefixOf t = true) (v : Bytes) :
    p.isPrefixOf (t ++ v) = true ∧ p.length ≤ t.length := by
  rw [List.isPrefixOf_iff_prefix] at h ⊢
  exact ⟨h.trans (List.prefix_append t v), h.length_le⟩

/-- English: Decoding a record never reads past the record: if it succeeds on t, the record fits in t and decoding gives the same result whatever follows t. -/
theorem decodeRecord_append {t : Bytes} {o : List (WriteOp Bytes)} {m : Nat}
    (h : decodeRecord t = some (o, m)) :
    m ≤ t.length ∧ ∀ v, decodeRecord (t ++ v) = some (o, m) := by
  unfold decodeRecord at h
  by_cases hm : magic.isPrefixOf t = true
  · have hm4 := (isPrefixOf_append_of hm []).2
    simp only [hm, ↓reduceIte, bind, Option.bind] at h
    cases h1 : unstuffN 4 (t.drop magic.length) with
    | none => rw [h1] at h; simp at h
    | some p1 =>
      obtain ⟨lb, u1⟩ := p1
      rw [h1] at h; simp only at h
      cases h2 : readU32le lb with
      | none => rw [h2] at h; simp at h
      | some q =>
        obtain ⟨len, q2⟩ := q
        rw [h2] at h; simp only at h
        cases h3 : unstuffN (len + 4) ((t.drop magic.length).drop u1) with
        | none => rw [h3] at h; simp at h
        | some p3 =>
          obtain ⟨more, u2⟩ := p3
          rw [h3] at h; simp only at h
          obtain ⟨b1, s1⟩ := unstuffN_append _ _ h1
          obtain ⟨b3, s3⟩ := unstuffN_append _ _ h3
          simp only [List.length_drop] at b1 b3
          have hm_eq : m = magic.length + u1 + u2 := by
            split at h
            · cases hd : decodePayload (List.take len more) with
              | none => rw [hd] at h; simp at h
              | some ops =>
                rw [hd] at h; simp only at h
                split at h
                · simp [pure] at h; omega
                · simp at h
            · simp at h
          refine ⟨by omega, fun v => ?_⟩
          unfold decodeRecord
          have hmv := (isPrefixOf_append_of hm v).1
          have d1 : (t ++ v).drop magic.length = t.drop magic.length ++ v :=
            List.drop_append_of_le_length hm4
          have d2 : (t.drop magic.length ++ v).drop u1 = (t.drop magic.length).drop u1 ++ v :=
            List.drop_append_of_le_length (by simp; omega)
          simp only [hmv, ↓reduceIte, bind, Option.bind, d1, s1, h2, d2, s3]
          exact h
  · simp only [hm] at h; simp at h

/-- English: Dropping at least all of l1 from l1 followed by l2 drops the rest from l2. -/
theorem drop_append_right {l1 l2 : Bytes} {q : Nat} (h : l1.length ≤ q) :
    (l1 ++ l2).drop q = l2.drop (q - l1.length) := by
  induction l1 generalizing q with
  | nil => simp
  | cons a l1 ih =>
    cases q with
    | zero => simp at h
    | succ q => simp only [List.cons_append, List.drop_succ_cons, List.length_cons]; simp at h; rw [ih h]; congr 1; omega

/-- English: Every byte string that decodes as a record starts with the magic number. -/
theorem magic_of_decodeRecord {b : Bytes} (h : (decodeRecord b).isSome = true) :
    magic.IsPrefix b := by
  by_cases hm : magic.isPrefixOf b = true
  · exact List.isPrefixOf_iff_prefix.mp hm
  · unfold decodeRecord at h; simp [hm] at h

/-- English: A strict prefix of a valid record (a torn write) never decodes as a record. -/
theorem decodeRecord_torn {ops : List (WriteOp Bytes)} (hops : validBatch ops = true) {t : Bytes}
    (ht : t.IsPrefix (encodeRecord ops)) (hlt : t.length < (encodeRecord ops).length) :
    decodeRecord t = none := by
  cases hd : decodeRecord t with
  | none => rfl
  | some r =>
    obtain ⟨o, m⟩ := r
    obtain ⟨hle, hv⟩ := decodeRecord_append hd
    obtain ⟨u, hu⟩ := ht
    have h1 := hv u
    rw [hu] at h1
    have h2 := decodeRecord_encodeRecord hops []
    rw [List.append_nil, h1] at h2
    simp at h2; omega

/-- English: Torn tail (R11, R12). If a crash leaves only part of the next record, recovery
opens with exactly the earlier records and ignores the partial one. This holds whatever the
stored keys and values are. -/
theorem recover_torn_tail {bs : List (List (WriteOp Bytes))}
    (h : ∀ ops ∈ bs, validBatch ops = true) {ops : List (WriteOp Bytes)}
    (hops : validBatch ops = true) {t : Bytes} (ht : t.IsPrefix (encodeRecord ops))
    (hlt : t.length < (encodeRecord ops).length) :
    recover (encodeLog bs ++ t) = .ok bs (encodeLog bs).length t.length := by
  have hd := decodeRecord_torn hops ht hlt
  have hrt : readRecords t = ([], 0) := by rw [readRecords, hd]
  have hrr := readRecords_encodeLog h t
  rw [hrt] at hrr; simp only [List.append_nil, Nat.add_zero] at hrr
  unfold recover
  rw [hrr]; simp only
  have hany : ((List.range (encodeLog bs ++ t).length).any
      (fun q => decide ((encodeLog bs).length < q) && validRecordAt (encodeLog bs ++ t) q)) = false := by
    rw [List.any_eq_false]
    intro q hq hc
    simp only [List.mem_range, List.length_append] at hq
    simp only [Bool.and_eq_true, decide_eq_true_eq] at hc
    obtain ⟨hpq, hvr⟩ := hc
    unfold validRecordAt at hvr
    have hdrop : (encodeLog bs ++ t).drop q = t.drop (q - (encodeLog bs).length) :=
      drop_append_right (by omega)
    rw [hdrop] at hvr
    have hmag := magic_of_decodeRecord hvr
    obtain ⟨u, hu⟩ := ht
    have : magic.IsPrefix ((encodeRecord ops ++ []).drop (q - (encodeLog bs).length)) := by
      rw [List.append_nil, ← hu, List.drop_append_of_le_length (by omega)]
      exact hmag.trans (List.prefix_append _ _)
    exact magic_only_at_start ops [] (by omega) (by omega) this
  rw [hany]; simp

/-- English: Corruption (R12). If a bad record sits between valid records, recovery refuses
and reports the bad record's offset. -/
theorem recover_corrupt {bs cs : List (List (WriteOp Bytes))}
    (hbs : ∀ ops ∈ bs, validBatch ops = true) (hcs : ∀ ops ∈ cs, validBatch ops = true)
    (hne : cs ≠ []) {g : Bytes} (hg : decodeRecord (g ++ encodeLog cs) = none) :
    recover (encodeLog bs ++ g ++ encodeLog cs) = .corrupt (encodeLog bs).length := by
  obtain ⟨c0, cs', rfl⟩ := List.exists_cons_of_ne_nil hne
  have hc0 := hcs c0 (by simp)
  have hdC : decodeRecord (encodeLog (c0 :: cs')) = some (c0, (encodeRecord c0).length) := by
    rw [encodeLog_cons]; exact decodeRecord_encodeRecord hc0 _
  have hgne : g ≠ [] := by rintro rfl; rw [List.nil_append, hdC] at hg; simp at hg
  have hglen : 0 < g.length := by cases g <;> simp_all
  have hrt : readRecords (g ++ encodeLog (c0 :: cs')) = ([], 0) := by rw [readRecords, hg]
  have hrr := readRecords_encodeLog hbs (g ++ encodeLog (c0 :: cs'))
  rw [hrt] at hrr; simp only [List.append_nil, Nat.add_zero] at hrr
  unfold recover
  rw [List.append_assoc, hrr]; simp only
  have hClen : 4 ≤ (encodeLog (c0 :: cs')).length := by
    rw [encodeLog_cons, List.length_append]; have := encodeRecord_length_pos c0; omega
  have hany : ((List.range (encodeLog bs ++ (g ++ encodeLog (c0 :: cs'))).length).any
      (fun q => decide ((encodeLog bs).length < q) &&
        validRecordAt (encodeLog bs ++ (g ++ encodeLog (c0 :: cs'))) q)) = true := by
    rw [List.any_eq_true]
    refine ⟨(encodeLog bs).length + g.length, ?_, ?_⟩
    · simp only [List.mem_range, List.length_append]; omega
    · simp only [Bool.and_eq_true, decide_eq_true_eq]
      refine ⟨by omega, ?_⟩
      unfold validRecordAt
      rw [← List.append_assoc, drop_append_right (by simp)]
      simp [hdC]
  rw [hany]; simp

end LeanKV.Spec
