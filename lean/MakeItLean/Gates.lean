import Lean

/-!
# MakeItLean gates

Spec gates (Stage 1–2), run as commands at the end of an app's spec aggregator module:

    #assert_english_docs MyApp.Spec           -- every declaration has an `English:` doc
    #assert_holes_only_in_theorems MyApp.Spec -- no definition uses an implementation hole
    #assert_spec_axioms MyApp.Spec            -- only theorems that name a hole may be open

Verified-code audit (Stage 6), run in the implementation package:

    #audit_verified MyAppImpl.Core MyAppImpl.Proofs forbid_imports MyAppImpl.Shell

An **implementation hole** is a declaration whose doc comment contains `IMPLEMENTATION HOLE`.
Every gate has a negative test in `MakeItLeanTest/` (planted violations it must reject).
-/

open Lean Elab Command Meta

namespace MakeItLean

/-- Module of a constant, if it was imported (not defined in the current file). -/
def moduleOf (env : Environment) (n : Name) : Option Name := do
  let idx ← env.getModuleIdxFor? n
  env.header.moduleNames[idx.toNat]?

/-- Is `n`, or a name it is nested under, an instance? (Covers `deriving` helpers.) -/
def underInstance (env : Environment) : Name → Bool
  | .anonymous => false
  | n@(.str p _) | n@(.num p _) => isInstanceCore env n || underInstance env p

/-- Is `n` the auto-generated constructor of a structure? -/
def isStructureCtor (env : Environment) (n : Name) : Bool :=
  match env.find? n with
  | some (.ctorInfo ci) => isStructure env ci.induct
  | _ => false

/-- Declarations a human should see documented (not compiler-generated). -/
def isUserFacing (env : Environment) (n : Name) : Bool :=
  !n.isInternalDetail && !isAuxRecursor env n && !isNoConfusion env n && !isRecCore env n &&
  !underInstance env n && !isStructureCtor env n && !Meta.isMatcherCore env n &&
  !(`injEq).isSuffixOf n && !(`inj).isSuffixOf n && !(`sizeOf_spec).isSuffixOf n &&
  !(`ctorIdx).isSuffixOf n

/-- Constants defined in modules under `pfx`. -/
def constantsUnder (env : Environment) (pfx : Name) : List (Name × ConstantInfo) :=
  env.constants.toList.filter fun (n, _) =>
    match moduleOf env n with
    | some m => pfx.isPrefixOf m
    | none => false

/-- `#assert_english_docs Pfx`: every user-facing declaration under `Pfx` has an `English:` doc. -/
elab "#assert_english_docs " pfx:ident : command => do
  let env ← getEnv
  let mut missing := #[]
  for (n, _) in constantsUnder env pfx.getId do
    unless isUserFacing env n do continue
    let some _ ← findDeclarationRanges? n | continue
    let ok : Bool := match ← findDocString? env n with
      | some d => "English:".toList.isPrefixOf (d.toList.dropWhile Char.isWhitespace)
      | none => false
    unless ok do missing := missing.push n
  if missing.isEmpty then logInfo m!"English-doc gate: OK for modules under {pfx.getId}"
  else throwError m!"English-doc gate: {missing.size} declaration(s) lack an `English:` doc: \
    {(missing.qsort Name.lt).toList}"

/-- The implementation holes under `pfx`: declarations documented `IMPLEMENTATION HOLE`. -/
def holeNames (pfx : Name) : CommandElabM (Array Name) := do
  let env ← getEnv
  let mut hs := #[]
  for (n, _) in constantsUnder env pfx do
    if let some d ← findDocString? env n then
      if (d.splitOn "IMPLEMENTATION HOLE").length > 1 then hs := hs.push n
  return hs

/-- `#assert_holes_only_in_theorems Pfx`: no definition (including compiler-generated helpers)
uses an implementation hole. A definition that did would compile differently once the hole is
filled, and `lake comparator` would reject every solution. -/
elab "#assert_holes_only_in_theorems " pfx:ident : command => do
  let env ← getEnv
  let holes ← holeNames pfx.getId
  if holes.isEmpty then throwError "Hole gate: no implementation holes found under {pfx.getId}"
  let mut bad := #[]
  for (n, ci) in constantsUnder env pfx.getId do
    if holes.contains n then continue
    let .defnInfo d := ci | continue
    let used := d.value.getUsedConstants.filter holes.contains
    unless used.isEmpty do bad := bad.push (n, used)
  if bad.isEmpty then
    logInfo m!"Hole gate: OK ({holes.size} holes, used only in theorem statements)"
  else throwError m!"Hole gate: definitions use implementation holes: {(bad.qsort (fun a b => Name.lt a.1 b.1)).toList}"

def standardAxioms : List Name := [``propext, ``Quot.sound, ``Classical.choice]

/-- `#assert_spec_axioms Pfx`: theorems whose *statement* names a hole are the implementation's
obligations and may be open (`sorry`); every other theorem must be proven with only `propext`,
`Quot.sound`, `Classical.choice`. -/
elab "#assert_spec_axioms " pfx:ident : command => do
  let env ← getEnv
  let holes ← holeNames pfx.getId
  let mut bad := #[]
  let mut obligations := #[]
  let mut n := 0
  for (nm, ci) in constantsUnder env pfx.getId do
    unless ci matches .thmInfo _ do continue
    n := n + 1
    let isObligation := ci.type.getUsedConstants.any holes.contains
    if isObligation then obligations := obligations.push nm
    let axs ← liftCoreM (collectAxioms nm)
    for a in axs do
      unless standardAxioms.contains a || (isObligation && a == ``sorryAx) do
        bad := bad.push s!"{nm} uses {a}"
  if bad.isEmpty then
    logInfo m!"Spec-axiom gate: OK ({n} theorems; {obligations.size} obligations open)"
  else throwError m!"Spec-axiom gate: {(bad.qsort (· < ·)).toList}"

syntax (name := auditVerified) "#audit_verified " (ident)+ " forbid_imports " ident : command

/-- `#audit_verified A B … forbid_imports S`: in modules under `A`, `B`, …, every theorem uses
only the three standard axioms; no declaration is `unsafe`, `opaque` (which is what `partial def`
compiles to), `@[implemented_by]` or `@[extern]`; and no such module imports a module under `S`. -/
@[command_elab auditVerified] def elabAuditVerified : CommandElab := fun stx => do
  let pfxs := stx[1].getArgs.map (·.getId)
  let shell := stx[3].getId
  let env ← getEnv
  let verified (m : Name) := pfxs.any (·.isPrefixOf m)
  let mut bad := #[]
  let mut nThm := 0
  for (n, ci) in env.constants.toList do
    let some m := moduleOf env n | continue
    unless verified m do continue
    if n.isInternalDetail || (`ctorIdx).isSuffixOf n then continue
    if ci.isUnsafe then bad := bad.push s!"unsafe: {n}"
    if ci matches .opaqueInfo _ then bad := bad.push s!"opaque/partial: {n}"
    if isExtern env n then bad := bad.push s!"extern: {n}"
    if (Compiler.implementedByAttr.getParam? env n).isSome then bad := bad.push s!"implemented_by: {n}"
    if ci matches .thmInfo _ then
      nThm := nThm + 1
      for a in ← liftCoreM (collectAxioms n) do
        unless standardAxioms.contains a do bad := bad.push s!"axiom {a} used by {n}"
  for i in [0:env.header.moduleNames.size] do
    let m := env.header.moduleNames[i]!
    if verified m then
      for imp in env.header.moduleData[i]!.imports do
        if shell.isPrefixOf imp.module then bad := bad.push s!"{m} imports {imp.module}"
  if bad.isEmpty then
    logInfo m!"Verified-code audit: OK ({nThm} theorems on standard axioms; no unsafe/partial/opaque/implemented_by/extern; {shell} not imported)"
  else throwError m!"Verified-code audit FAILED:\n{"\n".intercalate (bad.qsort (· < ·)).toList}"

end MakeItLean
