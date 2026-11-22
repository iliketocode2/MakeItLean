import LeanKVSol.Base.Wire

/-!
# LeanKV core: request-line splitting on `ByteArray` (Stage 7)

The spec's `splitSpaces` recurses once per byte, which overflows the stack on a large batch line
(a valid 10,000-write batch is ~60 MB of text). `splitBA` splits iteratively on the array.
`parseLine` is the spec's parser with this splitter. Proof-licensed: `parseLine l =
parseRequest (toBytes l)` for every line (`Proofs/Line.lean`).
-/

namespace LeanKV.Core
open LeanKV.Spec

/-- Split `l` at spaces from index `i`, the current token starting at `s`, appending finished
tokens to `acc`. Tail-recursive. -/
def splitBA (l : ByteArray) (i s : Nat) (acc : Array Bytes) : List Bytes :=
  if h : i < l.size then
    if l[i] == 0x20 then splitBA l (i + 1) (i + 1) (acc.push (toBytes (l.extract s i)))
    else splitBA l (i + 1) s acc
  else (acc.push (toBytes (l.extract s l.size))).toList
termination_by l.size - i

/-- Parse a request line given as bytes. Equal to the spec's `parseRequest`. -/
def parseLine (l : ByteArray) : Option (Request Bytes) :=
  let ts := splitBA l 0 0 #[]
  if ts.any (·.isEmpty) then none else parseRequestTokens ts

end LeanKV.Core
