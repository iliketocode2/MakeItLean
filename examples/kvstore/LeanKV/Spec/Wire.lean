import LeanKV.Spec.Model

/-!
# LeanKV spec: text encoding, grammar and exit codes (R14, R15, R22)

The CLI and the server share one line format. A line is a list of tokens separated by single
spaces, without its terminating newline. Lines are byte strings, because stdin delivers bytes.
Any byte outside the grammar makes the line a usage error.

Syntax only: the parser does not check size limits. A well-formed `put` with an empty key
parses fine, and the state machine (`step`) then answers `limitError`.
-/

namespace LeanKV.Spec

/-! ## Byte-string tokens -/

/-- English: A byte is printed as itself when it is a visible ASCII character (0x21–0x7E)
other than backslash and double quote. -/
def isPlain (b : UInt8) : Bool := 0x21 ≤ b && b ≤ 0x7E && b != 0x5C && b != 0x22

/-- English: The lowercase hex digit for a number from 0 to 15. -/
def hexDigit (n : Nat) : UInt8 :=
  if n < 10 then (0x30 + n).toUInt8 else (0x61 + (n - 10)).toUInt8

/-- English: The value of a hex digit, accepting upper or lower case; nothing if the byte is
not a hex digit. -/
def hexValue (c : UInt8) : Option Nat :=
  if 0x30 ≤ c && c ≤ 0x39 then some (c.toNat - 0x30)
  else if 0x61 ≤ c && c ≤ 0x66 then some (c.toNat - 0x61 + 10)
  else if 0x41 ≤ c && c ≤ 0x46 then some (c.toNat - 0x41 + 10)
  else none

/-- English: How one byte is written (R22). Plain bytes are written as themselves, backslash
as `\\`, newline as `\n`, tab as `\t`, and every other byte as `\xNN` with two lowercase hex
digits. -/
def escapeByte (b : UInt8) : Bytes :=
  if isPlain b then [b]
  else if b == 0x5C then [0x5C, 0x5C]
  else if b == 0x0A then [0x5C, 0x6E]
  else if b == 0x09 then [0x5C, 0x74]
  else [0x5C, 0x78, hexDigit (b.toNat / 16), hexDigit (b.toNat % 16)]

/-- English: How a byte string is written as one token (R22). The empty string is written
`""`; any other string is written byte by byte with `escapeByte`. -/
def encodeBytes (bs : Bytes) : Bytes :=
  if bs.isEmpty then [0x22, 0x22] else bs.flatMap escapeByte

/-- English: Undo the escaping of a non-empty token. Fails on a bare `"`, a byte outside
0x21–0x7E, or a backslash not followed by `\`, `n`, `t` or `x` and two hex digits. -/
def unescape : Bytes → Option Bytes
  | [] => some []
  | 0x5C :: 0x5C :: rest => (0x5C :: ·) <$> unescape rest
  | 0x5C :: 0x6E :: rest => (0x0A :: ·) <$> unescape rest
  | 0x5C :: 0x74 :: rest => (0x09 :: ·) <$> unescape rest
  | 0x5C :: 0x78 :: h :: l :: rest =>
    match hexValue h, hexValue l with
    | some hv, some lv => ((16 * hv + lv).toUInt8 :: ·) <$> unescape rest
    | _, _ => none
  | b :: rest => if isPlain b then (b :: ·) <$> unescape rest else none

/-- English: Read one token as a byte string (R22). `""` is the empty string; any other
token is unescaped. The empty token is not a byte string. -/
def decodeBytes (t : Bytes) : Option Bytes :=
  if t == [0x22, 0x22] then some [] else if t.isEmpty then none else unescape t

/-! ## Numbers and keywords -/

/-- English: A natural number written in decimal, with no leading zeros. -/
def printNat (n : Nat) : Bytes :=
  if n < 10 then [(0x30 + n).toUInt8] else printNat (n / 10) ++ [(0x30 + n % 10).toUInt8]
termination_by n
decreasing_by omega

/-- English: Read a non-empty string of decimal digits as a number. -/
def parseNat (t : Bytes) : Option Nat :=
  if t.isEmpty then none
  else t.foldl (fun acc d => do
    let a ← acc
    if 0x30 ≤ d && d ≤ 0x39 then some (10 * a + (d.toNat - 0x30)) else none) (some 0)

/-- English: The keyword `get`. -/
def kwGet : Bytes := [0x67, 0x65, 0x74]
/-- English: The keyword `put`. -/
def kwPut : Bytes := [0x70, 0x75, 0x74]
/-- English: The keyword `delete`. -/
def kwDelete : Bytes := [0x64, 0x65, 0x6C, 0x65, 0x74, 0x65]
/-- English: The keyword `scan`. -/
def kwScan : Bytes := [0x73, 0x63, 0x61, 0x6E]
/-- English: The keyword `batch`. -/
def kwBatch : Bytes := [0x62, 0x61, 0x74, 0x63, 0x68]
/-- English: The keyword `check`. -/
def kwCheck : Bytes := [0x63, 0x68, 0x65, 0x63, 0x6B]
/-- English: The reserved token `\inf`, meaning an unbounded scan. It cannot be confused with
a byte string, because `\i` is not a valid escape. -/
def kwInf : Bytes := [0x5C, 0x69, 0x6E, 0x66]
/-- English: The reply word `OK`. -/
def kwOK : Bytes := [0x4F, 0x4B]
/-- English: The reply word `VALUE`. -/
def kwValue : Bytes := [0x56, 0x41, 0x4C, 0x55, 0x45]
/-- English: The reply word `NOTFOUND`. -/
def kwNotFound : Bytes := [0x4E, 0x4F, 0x54, 0x46, 0x4F, 0x55, 0x4E, 0x44]
/-- English: The reply word `PAIRS`. -/
def kwPairs : Bytes := [0x50, 0x41, 0x49, 0x52, 0x53]
/-- English: The reply word `LOG`. -/
def kwLog : Bytes := [0x4C, 0x4F, 0x47]
/-- English: The reply word `ERR`. -/
def kwErr : Bytes := [0x45, 0x52, 0x52]
/-- English: The error kind `USAGE`. -/
def kwUsage : Bytes := [0x55, 0x53, 0x41, 0x47, 0x45]
/-- English: The error kind `LIMIT`. -/
def kwLimit : Bytes := [0x4C, 0x49, 0x4D, 0x49, 0x54]
/-- English: The error kind `CORRUPT`. -/
def kwCorrupt : Bytes := [0x43, 0x4F, 0x52, 0x52, 0x55, 0x50, 0x54]
/-- English: The error kind `IO`. -/
def kwIO : Bytes := [0x49, 0x4F]
/-- English: The field prefix `records=` in a `LOG` reply. -/
def kwRecordsEq : Bytes := [0x72, 0x65, 0x63, 0x6F, 0x72, 0x64, 0x73, 0x3D]
/-- English: The field prefix `bytes=` in a `LOG` reply. -/
def kwBytesEq : Bytes := [0x62, 0x79, 0x74, 0x65, 0x73, 0x3D]
/-- English: The field prefix `tail_ignored=` in a `LOG` reply. -/
def kwTailEq : Bytes :=
  [0x74, 0x61, 0x69, 0x6C, 0x5F, 0x69, 0x67, 0x6E, 0x6F, 0x72, 0x65, 0x64, 0x3D]

/-! ## Lines and tokens -/

/-- English: Split a line at every space. Always gives at least one piece; two spaces in a
row, or a space at either end, give an empty piece. -/
def splitSpaces : Bytes → List Bytes
  | [] => [[]]
  | b :: rest =>
    match splitSpaces rest with
    | [] => [[b]]
    | t :: ts => if b == 0x20 then [] :: t :: ts else (b :: t) :: ts

/-- English: Join tokens with single spaces. -/
def joinSpaces : List Bytes → Bytes
  | [] => []
  | [t] => t
  | t :: ts => t ++ 0x20 :: joinSpaces ts

/-- English: The tokens of a line. Fails on an empty line, a doubled space, or a space at
either end. -/
def tokenize (line : Bytes) : Option (List Bytes) :=
  let ts := splitSpaces line
  if ts.any (·.isEmpty) then none else some ts

/-- English: If token `t` starts with `p`, the rest of `t`. -/
def stripPrefix (p t : Bytes) : Option Bytes :=
  if p.isPrefixOf t then some (t.drop p.length) else none

/-! ## Requests -/

/-- English: A request line (R22): a state-machine command, or `check` (R21). -/
inductive Request (β : Type) where
  /-- English: A command for the state machine. -/
  | cmd (c : Cmd β)
  /-- English: The read-only `check` command (R21). -/
  | check
  deriving Repr, DecidableEq

/-- English: Change the byte-string representation inside a request, keeping its meaning. -/
def Request.map {β γ : Type} (f : β → γ) : Request β → Request γ
  | .cmd c => .cmd (c.map f)
  | .check => .check

/-- English: How the upper end of a scan is written: `\inf`, or the key as a token. -/
def printUpper : Upper Bytes → Bytes
  | .unbounded => kwInf
  | .below hi => encodeBytes hi

/-- English: Read the upper end of a scan. -/
def parseUpper (t : Bytes) : Option (Upper Bytes) :=
  if t == kwInf then some .unbounded else .below <$> decodeBytes t

/-- English: How one write in a batch is written: `put K V` or `delete K`. -/
def opTokens : WriteOp Bytes → List Bytes
  | .put k v => [kwPut, encodeBytes k, encodeBytes v]
  | .delete k => [kwDelete, encodeBytes k]

/-- English: Read the writes of a batch, one `put K V` or `delete K` after another. -/
def parseOps : List Bytes → Option (List (WriteOp Bytes))
  | [] => some []
  | [_] => none
  | w :: k :: rest =>
    if w == kwDelete then do
      let k ← decodeBytes k
      let ops ← parseOps rest
      pure (.delete k :: ops)
    else if w == kwPut then
      match rest with
      | v :: rest' => do
        let k ← decodeBytes k
        let v ← decodeBytes v
        let ops ← parseOps rest'
        pure (.put k v :: ops)
      | [] => none
    else none

/-- English: The tokens of a request (R22): `get K`, `put K V`, `delete K`,
`scan LO HI LIMIT`, `batch OP…` or `check`. -/
def requestTokens : Request Bytes → List Bytes
  | .cmd (.get k) => [kwGet, encodeBytes k]
  | .cmd (.put k v) => [kwPut, encodeBytes k, encodeBytes v]
  | .cmd (.delete k) => [kwDelete, encodeBytes k]
  | .cmd (.scan lo hi limit) => [kwScan, encodeBytes lo, printUpper hi, printNat limit]
  | .cmd (.batch ops) => kwBatch :: ops.flatMap opTokens
  | .check => [kwCheck]

/-- English: How a request is written as a line. -/
def printRequest (r : Request Bytes) : Bytes := joinSpaces (requestTokens r)

/-- English: Read a request from its tokens. The first token picks the command; the rest
must match that command's arguments exactly. -/
def parseRequestTokens : List Bytes → Option (Request Bytes)
  | [] => none
  | w :: args =>
    if w == kwGet then
      match args with
      | [k] => (fun k => .cmd (.get k)) <$> decodeBytes k
      | _ => none
    else if w == kwPut then
      match args with
      | [k, v] => do pure (.cmd (.put (← decodeBytes k) (← decodeBytes v)))
      | _ => none
    else if w == kwDelete then
      match args with
      | [k] => (fun k => .cmd (.delete k)) <$> decodeBytes k
      | _ => none
    else if w == kwScan then
      match args with
      | [lo, hi, n] => do
        pure (.cmd (.scan (← decodeBytes lo) (← parseUpper hi) (← parseNat n)))
      | _ => none
    else if w == kwBatch then (fun ops => .cmd (.batch ops)) <$> parseOps args
    else if w == kwCheck then
      match args with
      | [] => some .check
      | _ => none
    else none

/-- English: Read a request line. Failure means a usage error (exit code 2). -/
def parseRequest (line : Bytes) : Option (Request Bytes) := tokenize line >>= parseRequestTokens

/-! ## Replies and exit codes -/

/-- English: A reply line (R22), covering every outcome of every command, including
corruption and I/O errors from the storage layer. -/
inductive Reply (β : Type) where
  /-- English: `OK`: a write succeeded. -/
  | ok
  /-- English: `VALUE V`: `get` found a value. -/
  | value (v : β)
  /-- English: `NOTFOUND`: `get` found nothing. -/
  | notFound
  /-- English: `PAIRS n K1 V1 … Kn Vn`: the result of a scan. -/
  | pairs (kvs : List (β × β))
  /-- English: `LOG records=R bytes=B tail_ignored=T`: the result of `check` (R21). -/
  | log (records validBytes tailIgnored : Nat)
  /-- English: `ERR USAGE detail`: the line did not parse. -/
  | usageError (detail : β)
  /-- English: `ERR LIMIT detail`: a size limit was broken. -/
  | limitError (detail : β)
  /-- English: `ERR CORRUPT p`: the log is corrupt at byte offset `p` (R12). -/
  | corrupt (offset : Nat)
  /-- English: `ERR IO detail`: an I/O error. -/
  | ioError (detail : β)
  deriving Repr, DecidableEq

/-- English: Change the byte-string representation inside a reply, keeping its meaning. -/
def Reply.map {β γ : Type} (f : β → γ) : Reply β → Reply γ
  | .ok => .ok
  | .value v => .value (f v)
  | .notFound => .notFound
  | .pairs kvs => .pairs (kvs.map (fun p => (f p.1, f p.2)))
  | .log r b t => .log r b t
  | .usageError d => .usageError (f d)
  | .limitError d => .limitError (f d)
  | .corrupt p => .corrupt p
  | .ioError d => .ioError (f d)

/-- English: The reply for a state-machine answer. A limit error carries an explanatory
`detail` chosen by the implementation; the detail is not part of the answer's meaning. -/
def Reply.ofResponse {β : Type} (detail : β) : Response β → Reply β
  | .ok => .ok
  | .value v => .value v
  | .notFound => .notFound
  | .pairs kvs => .pairs kvs
  | .limitError => .limitError detail

/-- English: The exit-code table (R14), the only definition of exit codes. 0 for success,
1 for not found, 2 for a usage or limit error, 3 for corruption, 4 for an I/O error. -/
def Reply.exitCode {β : Type} : Reply β → UInt8
  | .ok | .value _ | .pairs _ | .log .. => 0
  | .notFound => 1
  | .usageError _ | .limitError _ => 2
  | .corrupt _ => 3
  | .ioError _ => 4

/-- English: The tokens of a reply (R22). -/
def replyTokens : Reply Bytes → List Bytes
  | .ok => [kwOK]
  | .value v => [kwValue, encodeBytes v]
  | .notFound => [kwNotFound]
  | .pairs kvs => kwPairs :: printNat kvs.length :: kvs.flatMap (fun p => [encodeBytes p.1, encodeBytes p.2])
  | .log r b t => [kwLog, kwRecordsEq ++ printNat r, kwBytesEq ++ printNat b, kwTailEq ++ printNat t]
  | .usageError d => [kwErr, kwUsage, encodeBytes d]
  | .limitError d => [kwErr, kwLimit, encodeBytes d]
  | .corrupt p => [kwErr, kwCorrupt, printNat p]
  | .ioError d => [kwErr, kwIO, encodeBytes d]

/-- English: How a reply is written as a line. -/
def printReply (r : Reply Bytes) : Bytes := joinSpaces (replyTokens r)

/-- English: Read the key-value tokens of a `PAIRS` reply, two tokens per pair. -/
def parsePairTokens : List Bytes → Option (List (Bytes × Bytes))
  | [] => some []
  | [_] => none
  | k :: v :: rest => do
    let k ← decodeBytes k
    let v ← decodeBytes v
    let ps ← parsePairTokens rest
    pure ((k, v) :: ps)

/-- English: Read a reply from its tokens. The first token picks the reply kind; the rest must
match that kind exactly. -/
def parseReplyTokens : List Bytes → Option (Reply Bytes)
  | [] => none
  | w :: args =>
    if w == kwOK then
      match args with
      | [] => some .ok
      | _ => none
    else if w == kwNotFound then
      match args with
      | [] => some .notFound
      | _ => none
    else if w == kwValue then
      match args with
      | [v] => .value <$> decodeBytes v
      | _ => none
    else if w == kwPairs then
      match args with
      | n :: rest => do
        let n ← parseNat n
        let ps ← parsePairTokens rest
        if ps.length = n then pure (.pairs ps) else none
      | [] => none
    else if w == kwLog then
      match args with
      | [r, b, t] => do
        let r ← stripPrefix kwRecordsEq r >>= parseNat
        let b ← stripPrefix kwBytesEq b >>= parseNat
        let t ← stripPrefix kwTailEq t >>= parseNat
        pure (.log r b t)
      | _ => none
    else if w == kwErr then
      match args with
      | [kind, d] =>
        if kind == kwUsage then .usageError <$> decodeBytes d
        else if kind == kwLimit then .limitError <$> decodeBytes d
        else if kind == kwCorrupt then .corrupt <$> parseNat d
        else if kind == kwIO then .ioError <$> decodeBytes d
        else none
      | _ => none
    else none

/-- English: Read a reply line. -/
def parseReply (line : Bytes) : Option (Reply Bytes) := tokenize line >>= parseReplyTokens

/-! ## Required properties and their proofs (Stage 2) -/

/-- English: Reading back a printed hex digit gives the original number, for every number from 0 to 15. -/
theorem hexValue_hexDigit : ∀ n < 16, hexValue (hexDigit n) = some n := by decide

/-- English: A plain byte at the front of a token is read back as itself. -/
theorem unescape_plain {x : UInt8} (h : isPlain x = true) (r : Bytes) :
    unescape (x :: r) = (x :: ·) <$> unescape r := by
  have hx : x ≠ 0x5C := by intro e; subst e; simp [isPlain] at h
  rw [unescape]
  · split <;> simp_all
  all_goals (intros; simp_all)

/-- English: A byte is 16 times its high hex digit plus its low hex digit. -/
theorem byte_split (x : UInt8) : (16 * (x.toNat / 16) + x.toNat % 16).toUInt8 = x := by
  rw [Nat.div_add_mod]; simp

/-- English: Reading back an escaped byte gives the original byte, whatever follows it. -/
theorem unescape_escapeByte (x : UInt8) (r : Bytes) :
    unescape (escapeByte x ++ r) = (x :: ·) <$> unescape r := by
  unfold escapeByte
  split
  · exact unescape_plain (by assumption) r
  · split
    · rename_i h; simp at h; subst h; simp [unescape]
    · split
      · rename_i h; simp at h; subst h; simp [unescape]
      · split
        · rename_i h; simp at h; subst h; simp [unescape]
        · have h1 := hexValue_hexDigit (x.toNat / 16) (by have := x.toNat_lt; omega)
          have h2 := hexValue_hexDigit (x.toNat % 16) (Nat.mod_lt _ (by decide))
          simp only [List.cons_append, List.nil_append]
          rw [unescape]
          · show (match hexValue (hexDigit (x.toNat / 16)), hexValue (hexDigit (x.toNat % 16)) with
                | some hv, some lv => ((16 * hv + lv).toUInt8 :: ·) <$> unescape r
                | _, _ => none) = _
            rw [h1, h2]; simp only [byte_split]
          all_goals simp

/-- English: Every hex digit is a visible ASCII character. -/
theorem hexDigit_visible : ∀ n < 16, 0x21 ≤ hexDigit n ∧ hexDigit n ≤ 0x7E := by decide

/-- English: Every byte of an escaped byte is a visible ASCII character. -/
theorem escapeByte_visible (x : UInt8) : ∀ y ∈ escapeByte x, 0x21 ≤ y ∧ y ≤ 0x7E := by
  unfold escapeByte
  split
  · rename_i h; simp [isPlain] at h; simp; exact ⟨h.1.1.1, h.1.1.2⟩
  · split
    · simp
    · split
      · simp
      · split
        · simp
        · have h1 := hexDigit_visible (x.toNat / 16) (by have := x.toNat_lt; omega)
          have h2 := hexDigit_visible (x.toNat % 16) (Nat.mod_lt _ (by decide))
          intro y hy; simp at hy
          rcases hy with rfl | rfl | rfl | rfl
          · decide
          · decide
          · exact h1
          · exact h2

/-- English: Reading back an escaped byte string gives the original bytes. -/
theorem unescape_flatMap (bs : Bytes) : unescape (bs.flatMap escapeByte) = some bs := by
  induction bs with
  | nil => rfl
  | cons x xs ih => rw [List.flatMap_cons, unescape_escapeByte, ih]; rfl

/-- English: An escaped byte is never empty. -/
theorem escapeByte_ne_nil (x : UInt8) : escapeByte x ≠ [] := by
  unfold escapeByte; split <;> (try split) <;> (try split) <;> (try split) <;> simp

/-- English: Decoding an encoded byte string gives back the same bytes (R22). -/
theorem decodeBytes_encodeBytes (b : Bytes) : decodeBytes (encodeBytes b) = some b := by
  unfold encodeBytes
  cases b with
  | nil => rfl
  | cons x xs =>
    simp only [List.isEmpty_cons, Bool.false_eq_true, ↓reduceIte]
    have hu := unescape_flatMap (x :: xs)
    have hne : (x :: xs).flatMap escapeByte ≠ [] := by
      rw [List.flatMap_cons]; intro h; exact escapeByte_ne_nil x (List.append_eq_nil_iff.mp h).1
    have hq : ((x :: xs).flatMap escapeByte == [0x22, 0x22]) = false := by
      apply beq_false_of_ne; intro h; rw [h] at hu; simp [unescape, isPlain] at hu
    unfold decodeBytes
    have he : ((x :: xs).flatMap escapeByte).isEmpty = false := by simpa using hne
    rw [hq]; simp only [he, Bool.false_eq_true, ↓reduceIte]; exact hu

/-- English: A token is visible when it is non-empty and every byte is a visible ASCII character (0x21–0x7E). In particular it has no space and no newline. -/
def Vis (t : Bytes) : Prop := t ≠ [] ∧ ∀ y ∈ t, 0x21 ≤ y ∧ y ≤ 0x7E

/-- English: An encoded byte string is a visible token. -/
theorem encodeBytes_vis (b : Bytes) : Vis (encodeBytes b) := by
  unfold encodeBytes
  cases b with
  | nil => exact ⟨by simp, by decide⟩
  | cons x xs =>
    simp only [List.isEmpty_cons, Bool.false_eq_true, ↓reduceIte]
    refine ⟨?_, ?_⟩
    · rw [List.flatMap_cons]; intro h; exact escapeByte_ne_nil x (List.append_eq_nil_iff.mp h).1
    · intro y hy; rw [List.mem_flatMap] at hy; obtain ⟨z, _, hz⟩ := hy; exact escapeByte_visible z y hz

/-- English: For a digit k, the byte 0x30+k is between `0` and `9` and reads back as k. -/
theorem digit_ok : ∀ k < 10, ((0x30 + k).toUInt8 : UInt8) ≥ 0x30 ∧ ((0x30 + k).toUInt8 : UInt8) ≤ 0x39 ∧
    ((0x30 + k).toUInt8 : UInt8).toNat - 0x30 = k := by decide

/-- English: Reading digits left to right: appending digit k to digits that read as n gives 10·n + k. -/
theorem parseNat_step (l : Bytes) (k : Nat) (hk : k < 10) (n : Nat)
    (h : l.foldl (fun acc d => do
      let a ← acc
      if 0x30 ≤ d && d ≤ 0x39 then some (10 * a + (d.toNat - 0x30)) else none) (some 0) = some n) :
    (l ++ [(0x30 + k).toUInt8]).foldl (fun acc d => do
      let a ← acc
      if 0x30 ≤ d && d ≤ 0x39 then some (10 * a + (d.toNat - 0x30)) else none) (some 0) =
      some (10 * n + k) := by
  obtain ⟨h1, h2, h3⟩ := digit_ok k hk
  generalize ((0x30 + k).toUInt8 : UInt8) = d at h1 h2 h3 ⊢
  rw [List.foldl_append, h]
  have h1' : (48 : UInt8) ≤ d := h1
  simp [h1', h2, h3]

/-- English: A printed number is never empty. -/
theorem printNat_ne_nil (n : Nat) : printNat n ≠ [] := by
  unfold printNat; split <;> simp

/-- English: Reading the digits of a printed number gives back the number. -/
theorem printNat_fold (n : Nat) :
    (printNat n).foldl (fun acc d => do
      let a ← acc
      if 0x30 ≤ d && d ≤ 0x39 then some (10 * a + (d.toNat - 0x30)) else none) (some 0) = some n := by
  induction n using Nat.strongRecOn with
  | _ n ih =>
    unfold printNat
    split
    · rename_i hn
      have := parseNat_step [] n hn 0 rfl
      simpa using this
    · rename_i hn
      have := parseNat_step _ (n % 10) (Nat.mod_lt _ (by decide)) (n / 10) (ih (n / 10) (by omega))
      rw [this]; congr 1; omega

/-- English: Reading a printed number gives back the same number. -/
theorem parseNat_printNat (n : Nat) : parseNat (printNat n) = some n := by
  unfold parseNat
  have : (printNat n).isEmpty = false := by simpa using printNat_ne_nil n
  simp only [this, Bool.false_eq_true, ↓reduceIte]
  exact printNat_fold n

/-- English: Every decimal digit is a visible ASCII character. -/
theorem digit_vis : ∀ k < 10, 0x21 ≤ ((0x30 + k).toUInt8 : UInt8) ∧ ((0x30 + k).toUInt8 : UInt8) ≤ 0x7E := by
  decide

/-- English: A printed number is a visible token. -/
theorem printNat_vis (n : Nat) : Vis (printNat n) := by
  refine ⟨printNat_ne_nil n, ?_⟩
  induction n using Nat.strongRecOn with
  | _ n ih =>
    unfold printNat
    split
    · rename_i hn; intro y hy; rw [List.mem_singleton.mp hy]; exact digit_vis n hn
    · intro y hy; rw [List.mem_append] at hy
      rcases hy with hy | hy
      · exact ih (n / 10) (by omega) y hy
      · rw [List.mem_singleton.mp hy]; exact digit_vis (n % 10) (Nat.mod_lt _ (by decide))

/-- English: A visible token contains no space. -/
theorem Vis.no_space {t : Bytes} (h : Vis t) : (0x20 : UInt8) ∉ t := by
  intro hm; have := (h.2 _ hm).1; contradiction

/-- English: Splitting a line always gives at least one piece. -/
theorem splitSpaces_ne_nil (r : Bytes) : splitSpaces r ≠ [] := by
  cases r with
  | nil => simp [splitSpaces]
  | cons b rest =>
    unfold splitSpaces; split
    · simp
    · split <;> simp

/-- English: Splitting a space-free prefix followed by the rest joins the prefix onto the rest's first piece. -/
theorem splitSpaces_append (t r : Bytes) (ht : (0x20 : UInt8) ∉ t) :
    splitSpaces (t ++ r) = match splitSpaces r with
      | [] => [t]
      | u :: us => (t ++ u) :: us := by
  induction t with
  | nil =>
    cases h : splitSpaces r with
    | nil => exact absurd h (splitSpaces_ne_nil r)
    | cons u us => simp [h]
  | cons b bs ih =>
    have hb : b ≠ 0x20 := fun e => ht (by simp [e])
    have ih' := ih (fun h => ht (List.mem_cons_of_mem _ h))
    simp only [List.cons_append]
    conv => lhs; unfold splitSpaces
    rw [ih']
    cases h : splitSpaces r with
    | nil => exact absurd h (splitSpaces_ne_nil r)
    | cons u us => simp [hb]

/-- English: A line starting with a space splits into an empty piece followed by the pieces of the rest. -/
theorem splitSpaces_space (rest : Bytes) :
    splitSpaces (0x20 :: rest) = [] :: splitSpaces rest := by
  conv => lhs; unfold splitSpaces
  cases h : splitSpaces rest with
  | nil => exact absurd h (splitSpaces_ne_nil rest)
  | cons u us => simp

/-- English: Splitting a line made by joining visible tokens with spaces gives back the tokens. -/
theorem split_join : ∀ (toks : List Bytes), toks ≠ [] → (∀ t ∈ toks, Vis t) →
    splitSpaces (joinSpaces toks) = toks
  | [], h, _ => absurd rfl h
  | [t], _, hv => by
    have := splitSpaces_append t [] (hv t (by simp)).no_space
    simp only [List.append_nil] at this
    simp only [joinSpaces]; rw [this]; simp [splitSpaces]
  | t :: t2 :: ts, _, hv => by
    have hrest := split_join (t2 :: ts) (by simp) (fun x hx => hv x (List.mem_cons_of_mem _ hx))
    simp only [joinSpaces]
    rw [splitSpaces_append t _ (hv t (by simp)).no_space, splitSpaces_space]
    rw [show joinSpaces (t2 :: ts) = joinSpaces (t2 :: ts) from rfl] at hrest
    cases ts with
    | nil => simp [joinSpaces] at hrest ⊢; rw [hrest]
    | cons t3 ts' => simp only [joinSpaces] at hrest ⊢; rw [hrest]; simp

/-- English: Tokenizing a line made by joining visible tokens with spaces gives back the tokens. -/
theorem tokenize_join (toks : List Bytes) (hne : toks ≠ []) (hv : ∀ t ∈ toks, Vis t) :
    tokenize (joinSpaces toks) = some toks := by
  unfold tokenize
  rw [split_join toks hne hv]
  have : toks.any (·.isEmpty) = false := by
    rw [List.any_eq_false]; intro t ht; simpa using (hv t ht).1
  simp [this]

/-- English: Every keyword is a visible token. -/
theorem vis_kw : Vis kwGet ∧ Vis kwPut ∧ Vis kwDelete ∧ Vis kwScan ∧ Vis kwBatch ∧ Vis kwCheck ∧
    Vis kwInf ∧ Vis kwOK ∧ Vis kwValue ∧ Vis kwNotFound ∧ Vis kwPairs ∧ Vis kwLog ∧ Vis kwErr ∧
    Vis kwUsage ∧ Vis kwLimit ∧ Vis kwCorrupt ∧ Vis kwIO := by
  have v : ∀ t : Bytes, t ≠ [] → t.all (fun y => 0x21 ≤ y && y ≤ 0x7E) = true → Vis t := by
    intro t h1 h2; refine ⟨h1, fun y hy => ?_⟩
    have := List.all_eq_true.mp h2 y hy; simpa using this
  refine ⟨v _ (by decide) (by decide), v _ (by decide) (by decide), v _ (by decide) (by decide),
    v _ (by decide) (by decide), v _ (by decide) (by decide), v _ (by decide) (by decide),
    v _ (by decide) (by decide), v _ (by decide) (by decide), v _ (by decide) (by decide),
    v _ (by decide) (by decide), v _ (by decide) (by decide), v _ (by decide) (by decide),
    v _ (by decide) (by decide), v _ (by decide) (by decide), v _ (by decide) (by decide),
    v _ (by decide) (by decide), v _ (by decide) (by decide)⟩

/-- English: A `LOG` field (`records=`, `bytes=` or `tail_ignored=` followed by a number) is a visible token. -/
theorem kwEq_vis (p : Bytes) (hp : p ∈ [kwRecordsEq, kwBytesEq, kwTailEq]) (n : Nat) :
    Vis (p ++ printNat n) := by
  refine ⟨by simp [printNat_ne_nil], ?_⟩
  intro y hy; rw [List.mem_append] at hy
  rcases hy with hy | hy
  · simp only [List.mem_cons, List.not_mem_nil, or_false] at hp
    rcases hp with rfl | rfl | rfl <;> revert y <;> decide
  · exact (printNat_vis n).2 y hy

/-- English: The reserved token `\inf` is not a byte string. -/
theorem decodeBytes_kwInf : decodeBytes kwInf = none := by decide

/-- English: No encoded byte string is the reserved token `\inf`. -/
theorem encodeBytes_ne_kwInf (b : Bytes) : encodeBytes b ≠ kwInf := by
  intro h; have := decodeBytes_encodeBytes b; rw [h, decodeBytes_kwInf] at this; simp at this

/-- English: Reading a printed scan upper end gives back the original. -/
theorem parseUpper_printUpper (u : Upper Bytes) : parseUpper (printUpper u) = some u := by
  cases u with
  | unbounded => decide
  | below hi =>
    simp [parseUpper, printUpper, encodeBytes_ne_kwInf, decodeBytes_encodeBytes]

/-- English: Reading the printed writes of a batch gives back the original writes. -/
theorem parseOps_flatMap (ops : List (WriteOp Bytes)) : parseOps (ops.flatMap opTokens) = some ops := by
  induction ops with
  | nil => rfl
  | cons op ops ih =>
    cases op with
    | put k v =>
      have h1 : (kwPut == kwDelete) = false := by decide
      simp only [List.flatMap_cons, opTokens, List.cons_append, List.nil_append]
      unfold parseOps
      simp [h1, decodeBytes_encodeBytes, ih]
    | delete k =>
      simp only [List.flatMap_cons, opTokens, List.cons_append, List.nil_append]
      unfold parseOps
      simp [decodeBytes_encodeBytes, ih]

/-- English: A printed scan upper end is a visible token. -/
theorem upper_vis (u : Upper Bytes) : Vis (printUpper u) := by
  cases u with
  | unbounded => exact vis_kw.2.2.2.2.2.2.1
  | below hi => exact encodeBytes_vis hi

/-- English: Every token of a printed write is visible. -/
theorem opTokens_vis (op : WriteOp Bytes) : ∀ t ∈ opTokens op, Vis t := by
  intro t ht
  cases op with
  | put k v =>
    simp only [opTokens, List.mem_cons, List.not_mem_nil, or_false] at ht
    rcases ht with rfl | rfl | rfl
    · exact vis_kw.2.1
    · exact encodeBytes_vis _
    · exact encodeBytes_vis _
  | delete k =>
    simp only [opTokens, List.mem_cons, List.not_mem_nil, or_false] at ht
    rcases ht with rfl | rfl
    · exact vis_kw.2.2.1
    · exact encodeBytes_vis _

/-- English: Every token of a printed request is visible. -/
theorem requestTokens_vis (r : Request Bytes) : ∀ t ∈ requestTokens r, Vis t := by
  intro t ht
  rcases r with ⟨c⟩ | _
  · cases c with
    | get k =>
      simp only [requestTokens, List.mem_cons, List.not_mem_nil, or_false] at ht
      rcases ht with rfl | rfl
      · exact vis_kw.1
      · exact encodeBytes_vis _
    | put k v =>
      simp only [requestTokens, List.mem_cons, List.not_mem_nil, or_false] at ht
      rcases ht with rfl | rfl | rfl
      · exact vis_kw.2.1
      · exact encodeBytes_vis _
      · exact encodeBytes_vis _
    | delete k =>
      simp only [requestTokens, List.mem_cons, List.not_mem_nil, or_false] at ht
      rcases ht with rfl | rfl
      · exact vis_kw.2.2.1
      · exact encodeBytes_vis _
    | scan lo hi n =>
      simp only [requestTokens, List.mem_cons, List.not_mem_nil, or_false] at ht
      rcases ht with rfl | rfl | rfl | rfl
      · exact vis_kw.2.2.2.1
      · exact encodeBytes_vis _
      · exact upper_vis _
      · exact printNat_vis _
    | batch ops =>
      simp only [requestTokens, List.mem_cons, List.mem_flatMap] at ht
      rcases ht with rfl | ⟨op, _, hop⟩
      · exact vis_kw.2.2.2.2.1
      · exact opTokens_vis op t hop
  · simp only [requestTokens, List.mem_cons, List.not_mem_nil, or_false] at ht
    subst ht; exact vis_kw.2.2.2.2.2.1

/-- English: A printed request has at least one token. -/
theorem requestTokens_ne_nil (r : Request Bytes) : requestTokens r ≠ [] := by
  rcases r with ⟨c⟩ | _ <;> (try cases c) <;> simp [requestTokens]

/-- English: Parsing a printed request gives back exactly the original request (R22). -/
theorem parseRequest_printRequest (r : Request Bytes) : parseRequest (printRequest r) = some r := by
  unfold parseRequest printRequest
  rw [tokenize_join _ (requestTokens_ne_nil r) (requestTokens_vis r)]
  simp only [Option.bind_eq_bind, Option.bind_some]
  have d := decodeBytes_encodeBytes
  rcases r with ⟨c⟩ | _
  · cases c with
    | get k => simp [requestTokens, parseRequestTokens, d]
    | put k v =>
      have : (kwPut == kwGet) = false := by decide
      simp [requestTokens, parseRequestTokens, d, this]
    | delete k =>
      have h1 : (kwDelete == kwGet) = false := by decide
      have h2 : (kwDelete == kwPut) = false := by decide
      simp [requestTokens, parseRequestTokens, d, h1, h2]
    | scan lo hi n =>
      have h1 : (kwScan == kwGet) = false := by decide
      have h2 : (kwScan == kwPut) = false := by decide
      have h3 : (kwScan == kwDelete) = false := by decide
      simp [requestTokens, parseRequestTokens, d, h1, h2, h3, parseUpper_printUpper,
        parseNat_printNat]
    | batch ops =>
      have h1 : (kwBatch == kwGet) = false := by decide
      have h2 : (kwBatch == kwPut) = false := by decide
      have h3 : (kwBatch == kwDelete) = false := by decide
      have h4 : (kwBatch == kwScan) = false := by decide
      simp [requestTokens, parseRequestTokens, h1, h2, h3, h4, parseOps_flatMap]
  · decide

/-- English: A byte string is a prefix of itself followed by anything. -/
theorem isPrefixOf_self_append (p x : Bytes) : p.isPrefixOf (p ++ x) = true := by
  induction p with
  | nil => rfl
  | cons a p ih => simp [ih]

/-- English: Stripping prefix p from p followed by x gives x. -/
theorem stripPrefix_append (p x : Bytes) : stripPrefix p (p ++ x) = some x := by
  simp [stripPrefix, isPrefixOf_self_append]

/-- English: Reading the printed pairs of a `PAIRS` reply gives back the original pairs. -/
theorem parsePairTokens_flatMap (kvs : List (Bytes × Bytes)) :
    parsePairTokens (kvs.flatMap (fun p => [encodeBytes p.1, encodeBytes p.2])) = some kvs := by
  induction kvs with
  | nil => rfl
  | cons p kvs ih =>
    simp only [List.flatMap_cons, List.cons_append, List.nil_append]
    unfold parsePairTokens
    simp [decodeBytes_encodeBytes, ih]

/-- English: Every token of a printed reply is visible. -/
theorem replyTokens_vis (r : Reply Bytes) : ∀ t ∈ replyTokens r, Vis t := by
  intro t ht
  cases r with
  | ok => simp [replyTokens] at ht; subst ht; exact vis_kw.2.2.2.2.2.2.2.1
  | value v =>
    simp only [replyTokens, List.mem_cons, List.not_mem_nil, or_false] at ht
    rcases ht with rfl | rfl
    · exact vis_kw.2.2.2.2.2.2.2.2.1
    · exact encodeBytes_vis _
  | notFound => simp [replyTokens] at ht; subst ht; exact vis_kw.2.2.2.2.2.2.2.2.2.1
  | pairs kvs =>
    simp only [replyTokens, List.mem_cons, List.mem_flatMap] at ht
    rcases ht with rfl | rfl | ⟨p, _, hp⟩
    · exact vis_kw.2.2.2.2.2.2.2.2.2.2.1
    · exact printNat_vis _
    · simp only [List.not_mem_nil, or_false] at hp
      rcases hp with rfl | rfl <;> exact encodeBytes_vis _
  | log r b c =>
    simp only [replyTokens, List.mem_cons, List.not_mem_nil, or_false] at ht
    rcases ht with rfl | rfl | rfl | rfl
    · exact vis_kw.2.2.2.2.2.2.2.2.2.2.2.1
    · exact kwEq_vis _ (by simp) _
    · exact kwEq_vis _ (by simp) _
    · exact kwEq_vis _ (by simp) _
  | usageError d | limitError d | ioError d =>
    simp only [replyTokens, List.mem_cons, List.not_mem_nil, or_false] at ht
    rcases ht with rfl | rfl | rfl
    · exact vis_kw.2.2.2.2.2.2.2.2.2.2.2.2.1
    all_goals first
      | exact vis_kw.2.2.2.2.2.2.2.2.2.2.2.2.2.1
      | exact vis_kw.2.2.2.2.2.2.2.2.2.2.2.2.2.2.1
      | exact vis_kw.2.2.2.2.2.2.2.2.2.2.2.2.2.2.2.2
      | exact encodeBytes_vis _
  | corrupt p =>
    simp only [replyTokens, List.mem_cons, List.not_mem_nil, or_false] at ht
    rcases ht with rfl | rfl | rfl
    · exact vis_kw.2.2.2.2.2.2.2.2.2.2.2.2.1
    · exact vis_kw.2.2.2.2.2.2.2.2.2.2.2.2.2.2.2.1
    · exact printNat_vis _

/-- English: A printed reply has at least one token. -/
theorem replyTokens_ne_nil (r : Reply Bytes) : replyTokens r ≠ [] := by
  cases r <;> simp [replyTokens]

/-- English: Parsing a printed reply gives back exactly the original reply (R22). -/
theorem parseReply_printReply (r : Reply Bytes) : parseReply (printReply r) = some r := by
  unfold parseReply printReply
  rw [tokenize_join _ (replyTokens_ne_nil r) (replyTokens_vis r)]
  simp only [Option.bind_eq_bind, Option.bind_some]
  have d := decodeBytes_encodeBytes
  have n := parseNat_printNat
  cases r with
  | ok => decide
  | notFound => decide
  | value v =>
    have h1 : (kwValue == kwOK) = false := by decide
    have h2 : (kwValue == kwNotFound) = false := by decide
    simp only [replyTokens]; delta parseReplyTokens; simp [d, h1, h2]
  | pairs kvs =>
    have h1 : (kwPairs == kwOK) = false := by decide
    have h2 : (kwPairs == kwNotFound) = false := by decide
    have h3 : (kwPairs == kwValue) = false := by decide
    simp only [replyTokens]; delta parseReplyTokens; simp [n, h1, h2, h3, parsePairTokens_flatMap]
  | log a b c =>
    have h1 : (kwLog == kwOK) = false := by decide
    have h2 : (kwLog == kwNotFound) = false := by decide
    have h3 : (kwLog == kwValue) = false := by decide
    have h4 : (kwLog == kwPairs) = false := by decide
    simp only [replyTokens]; delta parseReplyTokens; simp [n, h1, h2, h3, h4, stripPrefix_append]
  | usageError e | limitError e | corrupt e | ioError e =>
    have h1 : (kwErr == kwOK) = false := by decide
    have h2 : (kwErr == kwNotFound) = false := by decide
    have h3 : (kwErr == kwValue) = false := by decide
    have h4 : (kwErr == kwPairs) = false := by decide
    have h5 : (kwErr == kwLog) = false := by decide
    have k1 : (kwLimit == kwUsage) = false := by decide
    have k2 : (kwCorrupt == kwUsage) = false := by decide
    have k3 : (kwCorrupt == kwLimit) = false := by decide
    have k4 : (kwIO == kwUsage) = false := by decide
    have k5 : (kwIO == kwLimit) = false := by decide
    have k6 : (kwIO == kwCorrupt) = false := by decide
    simp only [replyTokens]; delta parseReplyTokens; simp [d, n, h1, h2, h3, h4, h5, k1, k2, k3, k4, k5, k6]

/-- English: Joining visible tokens with spaces gives a line with no newline byte. -/
theorem join_no_newline : ∀ (toks : List Bytes), (∀ t ∈ toks, Vis t) →
    (0x0A : UInt8) ∉ joinSpaces toks
  | [], _ => by simp [joinSpaces]
  | [t], hv => fun h => by
    have := ((hv t (by simp)).2 _ (by simpa [joinSpaces] using h)).1; contradiction
  | t :: t2 :: ts, hv => by
    simp only [joinSpaces, List.mem_append, List.mem_cons, not_or]
    refine ⟨fun h => ?_, by decide, join_no_newline (t2 :: ts) (fun x hx => hv x (List.mem_cons_of_mem _ hx))⟩
    have := ((hv t (by simp)).2 _ h).1; contradiction

/-- English: A printed request or reply is a single line: it contains no newline byte, so
the server's one-line-per-command framing (R15) is safe. -/
theorem printed_no_newline (q : Request Bytes) (r : Reply Bytes) :
    (0x0A : UInt8) ∉ printRequest q ∧ (0x0A : UInt8) ∉ printReply r :=
  ⟨join_no_newline _ (requestTokens_vis q), join_no_newline _ (replyTokens_vis r)⟩

/-- English: An encoded byte string is a non-empty token made only of visible ASCII
characters, so it never contains a space or a newline (R22). -/
theorem encodeBytes_visible (b : Bytes) :
    encodeBytes b ≠ [] ∧ ∀ x ∈ encodeBytes b, 0x21 ≤ x ∧ x ≤ 0x7E := encodeBytes_vis b

end LeanKV.Spec
