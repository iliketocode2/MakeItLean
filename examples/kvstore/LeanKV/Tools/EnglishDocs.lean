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

/-- Is `n` the auto-generated constructor (`.mk`) of a structure? -/
def isStructureCtor (env : Environment) (n : Name) : Bool :=
  match env.find? n with
  | some (.ctorInfo ci) => isStructure env ci.induct
  | _ => false

/-- Is `n` a declaration a human should see documented? -/
def isUserFacing (env : Environment) (n : Name) : Bool :=
  !n.isInternalDetail &&
  !isAuxRecursor env n && !isNoConfusion env n && !isRecCore env n &&
  !underInstance env n && !isStructureCtor env n &&
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

/-- The spec's implementation holes: declarations whose doc says `IMPLEMENTATION HOLE`. -/
def holeNames (pfx : Name) : CommandElabM (Array Name) := do
  let env ← getEnv
  let mut hs := #[]
  for (n, _) in env.constants.toList do
    let some idx := env.getModuleIdxFor? n | continue
    let some mod := env.header.moduleNames[idx.toNat]? | continue
    unless pfx.isPrefixOf mod do continue
    if let some d ← findDocString? env n then
      if (d.splitOn "IMPLEMENTATION HOLE").length > 1 then
        hs := hs.push n
  return hs

/-- `#assert_holes_only_in_theorems Pfx`: no definition (including compiler-generated helpers)
in modules under `Pfx` may use an implementation hole. Holes may appear only in theorem
statements. A definition that used a hole would compile differently once the hole is filled,
and `lake comparator` would then reject every solution. -/
elab "#assert_holes_only_in_theorems " pfx:ident : command => do
  let env ← getEnv
  let holes ← holeNames pfx.getId
  if holes.isEmpty then throwError "no implementation holes found under {pfx.getId}"
  let mut bad := #[]
  for (n, ci) in env.constants.toList do
    let some idx := env.getModuleIdxFor? n | continue
    let some mod := env.header.moduleNames[idx.toNat]? | continue
    unless pfx.getId.isPrefixOf mod do continue
    if holes.contains n then continue
    let .defnInfo d := ci | continue
    let used := d.value.getUsedConstants.filter holes.contains
    unless used.isEmpty do bad := bad.push (n, used)
  if bad.isEmpty then
    logInfo m!"Hole gate: OK ({holes.size} holes, used only in theorem statements)"
  else
    throwError m!"Hole gate: definitions use implementation holes: {bad.toList}"

end LeanKV.Tools
