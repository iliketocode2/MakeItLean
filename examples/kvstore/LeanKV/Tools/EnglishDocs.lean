import Lean

/-!
# English-doc gate (Stage 1)

`#assert_english_docs Pfx` fails elaboration unless every user-facing declaration
in a module whose name starts with `Pfx` has a doc comment beginning with `English:`.

User-facing means: it has a source position, and it is not an instance, an
auto-generated auxiliary (recursor, `casesOn`, `noConfusion`, matcher, equation lemma, …)
or an internal name.

Candidate for extraction into the framework library (`lean/MakeItLean/`) in Phase 2.
-/

open Lean Elab Command Meta

namespace LeanKV.Tools

/-- Is `n`, or a name it is nested under, an instance? (Covers `deriving` helpers such as
`instReprCmd.repr`.) -/
def underInstance (env : Environment) : Name → Bool
  | .anonymous => false
  | n@(.str p _) | n@(.num p _) => isInstanceCore env n || underInstance env p

/-- Is `n` a declaration a human should see documented? -/
def isUserFacing (env : Environment) (n : Name) : Bool :=
  !n.isInternalDetail &&
  !isAuxRecursor env n && !isNoConfusion env n && !isRecCore env n &&
  !underInstance env n &&
  !Meta.isMatcherCore env n &&
  !(`injEq).isSuffixOf n && !(`inj).isSuffixOf n &&
  !(`sizeOf_spec).isSuffixOf n && !(`ctorIdx).isSuffixOf n

/-- The `Pfx`-prefixed modules' user-facing declarations that lack an `English:` doc. -/
def missingEnglishDocs (pfx : Name) : CommandElabM (Array Name) := do
  let env ← getEnv
  let mut missing := #[]
  for (n, _) in env.constants.toList do
    let some idx := env.getModuleIdxFor? n | continue
    let some mod := env.header.moduleNames[idx.toNat]? | continue
    unless pfx.isPrefixOf mod do continue
    unless isUserFacing env n do continue
    -- Declarations without a source range are compiler-generated.
    let some _ ← findDeclarationRanges? n | continue
    let doc? ← findDocString? env n
    let ok : Bool := match doc? with
      | some d => "English:".toList.isPrefixOf (d.toList.dropWhile Char.isWhitespace)
      | none => false
    unless ok do missing := missing.push n
  return missing.qsort Name.lt

/-- `#assert_english_docs Pfx`: error listing every undocumented declaration under `Pfx`. -/
elab "#assert_english_docs " pfx:ident : command => do
  let missing ← missingEnglishDocs pfx.getId
  if missing.isEmpty then
    logInfo m!"English-doc gate: OK for modules under {pfx.getId}"
  else
    throwError m!"English-doc gate: {missing.size} declaration(s) lack an `English:` doc:\n\
      {"\n".intercalate (missing.toList.map toString)}"

end LeanKV.Tools
