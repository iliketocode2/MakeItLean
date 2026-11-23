import Counter.Spec.Model

/-!
# Counter's text protocol (trusted, shared)

One command per line (`incr <name>`, `get <name>`), one answer per line (`VALUE <n>`, `ERR`,
`ERR USAGE`, `ERR IO`). The CLI, `serve` and the model oracle all use these two functions, so a
differential test of `serve` against the oracle compares like with like.
-/

namespace CounterImpl
open LeanKV.Spec Counter.Spec

/-- Parse a command from its words (`["incr", "a"]`); `none` for anything else. -/
def parseCmd : List String → Option (CCmd ByteArray)
  | ["incr", n] => some (.incr n.toUTF8)
  | ["get", n] => some (.get n.toUTF8)
  | _ => none

/-- The words of one protocol line (trailing newline and repeated spaces ignored). -/
def words (line : String) : List String :=
  (line.splitOn " ").filterMap fun w =>
    let w := (w.toList.filter (· != '\n')).asString
    if w.isEmpty then none else some w

/-- The answer line for a model answer. -/
def render : CResp → String
  | .value v => s!"VALUE {v}"
  | .error => "ERR"

end CounterImpl
