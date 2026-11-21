import LeanKV.Spec.Model
import LeanKV.Spec.Wire
import LeanKV.Spec.Log

/-!
# LeanKV spec: worked examples from the requirements (Stage 2)

Every example in `REQUIREMENTS.md`, checked against the reference model on every build with
`#guard`. If the model ever disagreed with the English examples, the build would fail.
-/

namespace LeanKV.Spec

/-- English: The bytes of an ASCII string, for writing examples. -/
def ascii (s : String) : Bytes := s.toUTF8.toList

/-- English: Four keys a, b, c, d, each stored with itself as its value (the R7 example). -/
def abcd : List (Cmd Bytes) := ["a", "b", "c", "d"].map fun k => .put (ascii k) (ascii k)

-- R2: "a" < "ab" < "b"
#guard bytesLt (ascii "a") (ascii "ab") && bytesLt (ascii "ab") (ascii "b")
#guard !bytesLt (ascii "b") (ascii "a")

-- R4: after `put a 1`, `get a` → 1 and `get b` → not found
#guard run [.put (ascii "a") (ascii "1"), .get (ascii "a"), .get (ascii "b")] ==
  [.ok, .value (ascii "1"), .notFound]

-- R5: `put a 1; put a 2; get a` → 2
#guard run [.put (ascii "a") (ascii "1"), .put (ascii "a") (ascii "2"), .get (ascii "a")] ==
  [.ok, .ok, .value (ascii "2")]

-- R6: `put a 1; delete a; get a` → not found; deleting a missing key is fine
#guard run [.put (ascii "a") (ascii "1"), .delete (ascii "a"), .get (ascii "a"),
  .delete (ascii "zz")] == [.ok, .ok, .notFound, .ok]

-- R7: keys a,b,c,d: `scan b d 10` → b,c; `scan a ∞ 2` → a,b
#guard (run (abcd ++ [.scan (ascii "b") (.below (ascii "d")) 10])).getLast? ==
  some (.pairs [(ascii "b", ascii "b"), (ascii "c", ascii "c")])
#guard (run (abcd ++ [.scan (ascii "a") .unbounded 2])).getLast? ==
  some (.pairs [(ascii "a", ascii "a"), (ascii "b", ascii "b")])

-- R7a: lo ≥ hi, or limit 0, give an empty result (a success); an empty lo means "from the start"
#guard (run (abcd ++ [.scan (ascii "c") (.below (ascii "b")) 5])).getLast? == some (.pairs [])
#guard (run (abcd ++ [.scan (ascii "a") .unbounded 0])).getLast? == some (.pairs [])
#guard (run (abcd ++ [.scan [] (.below (ascii "b")) 9])).getLast? ==
  some (.pairs [(ascii "a", ascii "a")])

-- R8: `batch [put x 1, delete x, put y 2]` → x not found, y = 2
#guard run [.batch [.put (ascii "x") (ascii "1"), .delete (ascii "x"), .put (ascii "y") (ascii "2")],
  .get (ascii "x"), .get (ascii "y")] == [.ok, .notFound, .value (ascii "2")]

-- R8 atomicity: a batch with one invalid op (empty key) changes nothing
#guard run [.batch [.put (ascii "z") (ascii "1"), .put [] (ascii "1")], .get (ascii "z")] ==
  [.limitError, .notFound]

-- R8a: the empty batch succeeds
#guard run [.batch []] == [.ok]

-- R1: empty key, 1025-byte key and 1 MiB + 1 value are rejected; the boundaries are accepted
#guard run [.put [] (ascii "v"), .get [], .delete []] == [.limitError, .limitError, .limitError]
#guard run [.put (List.replicate 1025 0x61) []] == [.limitError]
#guard run [.put (List.replicate 1024 0x61) []] == [.ok]
#guard run [.put (ascii "k") (List.replicate (1024 * 1024 + 1) 0)] == [.limitError]

-- R22: wire examples
#guard printRequest (.cmd (.scan [] .unbounded 0)) == ascii "scan \"\" \\inf 0"
#guard printRequest (.cmd (.put (ascii "a b") [0x00, 0x0A])) == ascii "put a\\x20b \\x00\\n"
#guard parseRequest (ascii "get \\x4A\\x4a") == some (.cmd (.get (ascii "JJ")))
#guard parseRequest (ascii "get  a") == none
#guard printReply (.log 3 120 0 : Reply Bytes) == ascii "LOG records=3 bytes=120 tail_ignored=0"

-- R14: the exit-code table
#guard [(Reply.ok : Reply Bytes), .notFound, .usageError [], .limitError [], .corrupt 0, .ioError []].map
  Reply.exitCode == [0, 1, 2, 2, 3, 4]

-- R12: a value containing a whole encoded record is still recovered correctly after a torn write
#guard
  let inner := encodeRecord [.put (ascii "a") (ascii "1")]
  let r := encodeRecord [.put (ascii "backup") inner]
  (List.range r.length).all fun n => recover (r.take n) == .ok [] 0 n

end LeanKV.Spec
