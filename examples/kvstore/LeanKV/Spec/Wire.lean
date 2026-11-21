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
def printNat (n : Nat) : Bytes := (Nat.toDigits 10 n).map (fun c => c.toNat.toUInt8)

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

/-! ## Required properties (proven in Stage 2) -/

/-- English: Decoding an encoded byte string gives back the same bytes (R22). -/
theorem decodeBytes_encodeBytes (b : Bytes) : decodeBytes (encodeBytes b) = some b := sorry

/-- English: An encoded byte string is a non-empty token made only of visible ASCII
characters, so it never contains a space or a newline (R22). -/
theorem encodeBytes_visible (b : Bytes) :
    encodeBytes b ≠ [] ∧ ∀ x ∈ encodeBytes b, 0x21 ≤ x ∧ x ≤ 0x7E := sorry

/-- English: Reading a printed number gives back the same number. -/
theorem parseNat_printNat (n : Nat) : parseNat (printNat n) = some n := sorry

/-- English: Parsing a printed request gives back exactly the original request (R22). -/
theorem parseRequest_printRequest (r : Request Bytes) : parseRequest (printRequest r) = some r :=
  sorry

/-- English: Parsing a printed reply gives back exactly the original reply (R22). -/
theorem parseReply_printReply (r : Reply Bytes) : parseReply (printReply r) = some r := sorry

/-- English: A printed request or reply is a single line: it contains no newline byte, so
the server's one-line-per-command framing (R15) is safe. -/
theorem printed_no_newline (q : Request Bytes) (r : Reply Bytes) :
    (0x0A : UInt8) ∉ printRequest q ∧ (0x0A : UInt8) ∉ printReply r := sorry

end LeanKV.Spec
