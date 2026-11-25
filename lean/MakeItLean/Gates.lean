import Lean

/-!
# MakeItLean gates

Spec gates (Stage 1–2), run as commands at the end of an app's spec aggregator module:

    #assert_english_docs MyApp.Spec           -- every declaration has an `English:` doc
    #assert_holes_only_in_theorems MyApp.Spec -- no definition uses an implementation hole
    #assert_spec_axioms MyApp.Spec            -- only theorems that name a hole may be open

Verified-code audit (Stage 6), run in the implementation package:

    #audit_verified MyAppImpl.Core MyAppImpl.Proofs forbid_imports MyAppImpl.Shell MyAppImpl.Text MyAppImpl.Oracle

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
obligations and may be open (`sorry`); every other theorem must be proven, and every definition
other than a hole must be complete, with only `propext`, `Quot.sound`, `Classical.choice`. -/
elab "#assert_spec_axioms " pfx:ident : command => do
  let env ← getEnv
  let holes ← holeNames pfx.getId
  let mut bad := #[]
  let mut obligations := #[]
  let mut n := 0
  for (nm, ci) in constantsUnder env pfx.getId do
    -- spec definitions (other than the holes) must be complete: a `sorry` in a precondition,
    -- postcondition or model would otherwise pass the gates and only fail at the comparator
    if ci matches .defnInfo _ && !holes.contains nm then
      for a in ← liftCoreM (collectAxioms nm) do
        unless standardAxioms.contains a do bad := bad.push s!"{nm} uses {a}"
      continue
    unless ci matches .thmInfo _ do continue
    if isUserFacing env nm then n := n + 1  -- report the app's own theorems, not generated lemmas
    let isObligation := ci.type.getUsedConstants.any holes.contains
    if isObligation then obligations := obligations.push nm
    let axs ← liftCoreM (collectAxioms nm)
    for a in axs do
      unless standardAxioms.contains a || (isObligation && a == ``sorryAx) do
        bad := bad.push s!"{nm} uses {a}"
  if bad.isEmpty then
    logInfo m!"Spec-axiom gate: OK ({n} theorems; {obligations.size} obligations open)"
  else throwError m!"Spec-axiom gate: {(bad.qsort (· < ·)).toList}"

syntax (name := assertContract) "#assert_contract " ident " (" ident* ")" " (" ident* ")" : command

/-- `#assert_contract Pfx (H…) (O…)`: the implementation holes under `Pfx` are
exactly `H…`, and the theorems whose statement names a hole (the obligations) are exactly `O…`.
`mil` runs this with the names in `mil.json`, so a theorem cannot dodge proof by mentioning a hole
while being left out of the list the comparator checks. -/
@[command_elab assertContract] def elabAssertContract : CommandElab := fun stx => do
  let pfx := stx[1].getId
  let declHoles := stx[3].getArgs.map (·.getId)
  let declObls := stx[6].getArgs.map (·.getId)
  let env ← getEnv
  let holes ← holeNames pfx
  let mut obls := #[]
  for (n, ci) in constantsUnder env pfx do
    if ci matches .thmInfo _ && ci.type.getUsedConstants.any holes.contains then obls := obls.push n
  let diff (a b : Array Name) := (a.filter (!b.contains ·)).qsort Name.lt |>.toList
  let mut bad := #[]
  for n in diff holes declHoles do bad := bad.push s!"hole {n} is not listed in mil.json"
  for n in diff declHoles holes do bad := bad.push s!"mil.json lists {n}, which is not an implementation hole"
  for n in diff obls declObls do bad := bad.push s!"theorem {n} names a hole but is not a listed obligation (the comparator would never check it)"
  for n in diff declObls obls do bad := bad.push s!"mil.json lists {n}, which is not a theorem naming a hole"
  if bad.isEmpty then logInfo m!"Contract gate: OK ({holes.size} holes, {obls.size} obligations, matching mil.json)"
  else throwError m!"Contract gate FAILED:\n{"\n".intercalate bad.toList}"

/-- Does `tok` look like a Lean name rather than prose, a command or a file? It is an identifier
with an underscore, an inner capital (`pickOk`) or a dot path (`LedgerImpl.pick`). -/
def looksLikeLeanName (tok : String) : Bool :=
  let cs := tok.toList
  let identChar (c : Char) := c.isAlphanum || c == '_' || c == '.' || c == '\'' || c == '!' || c == '?'
  let exts := [".lean", ".md", ".c", ".h", ".sh", ".py", ".json", ".log", ".lock", ".txt", ".ts", ".js", ".mjs",
    ".cjs", ".yml", ".yaml", ".toml"]
  match cs with
  | [] => false
  | c :: _ =>
    let keywords := ["implemented_by", "native_decide", "bv_decide", "extern", "partial_fixpoint"]
    (c.isAlpha || c == '_') && cs.all identChar && !exts.any (tok.endsWith ·) &&
    !keywords.contains tok && cs.any Char.isLower &&  -- skip error codes like `BAD_NAME`
    !tok.startsWith "__" &&  -- skip dunder words such as the JSON key `__proto__`
    (cs.contains '_' || cs.contains '.' ||
      (cs.zip cs.tail).any (fun (a, b) => a.isLower && b.isUpper))

/-- The `code spans` of a Markdown text. -/
def codeSpans (s : String) : List String :=
  (s.splitOn "`").zipIdx.filterMap fun (t, i) => if i % 2 == 1 then some t else none

/-- `#assert_trust_cites "TRUST.md" "appDir"`: every name in a code span of the trust manifest that
looks like a Lean name exists in the environment (as a full name or a namespace suffix), unless
it names a file in the app directory (`cli_test` for `tests/cli_test.sh`). A trust manifest that
cites a theorem that does not exist is claiming a proof nobody has. -/
elab "#assert_trust_cites " path:str dir:str : command => do
  let env ← getEnv
  unless ← System.FilePath.pathExists path.getString do
    throwError "Trust gate: {path.getString} does not exist (Stage 6 requires a trust manifest)"
  let text ← IO.FS.readFile path.getString
  let mut files : Std.HashSet String := {}
  for f in ← (System.FilePath.mk dir.getString).walkDir (fun p => pure (p.fileName != some ".lake")) do
    if let some stem := f.fileStem then files := files.insert stem
  let mut suffixes : Std.HashSet String := {}
  for (n, _) in env.constants.toList do
    let comps := n.components.map toString
    for i in [0:comps.length] do suffixes := suffixes.insert (".".intercalate (comps.drop i))
  for m in env.header.moduleNames do suffixes := suffixes.insert m.toString
  let toks := (codeSpans text).filter looksLikeLeanName |>.eraseDups
  -- `h.index` in prose: a field access on a short lowercase local; the field must exist
  let fieldOk (t : String) : Bool := match t.splitOn "." with
    | [v, f] => v.length ≤ 3 && v.toList.all Char.isLower && suffixes.contains f
    | _ => false
  let missing := toks.filter fun t => !suffixes.contains t && !files.contains t && !fieldOk t
  if missing.isEmpty then logInfo m!"Trust gate: OK ({toks.length} cited names exist)"
  else throwError m!"Trust gate: {path.getString} cites names that do not exist: {missing}"

syntax (name := auditVerified) "#audit_verified " (ident)+ " forbid_imports " (ident)+ : command

/-- `#audit_verified A B … forbid_imports S T …`: in modules under `A`, `B`, …, every theorem uses
only the three standard axioms; no declaration is `unsafe`, `opaque` (which is what `partial def`
compiles to), `@[implemented_by]` or `@[extern]`; and no such module imports a module under any of `S`, `T`, … (the trusted shell and the modules only it uses). -/
@[command_elab auditVerified] def elabAuditVerified : CommandElab := fun stx => do
  let pfxs := stx[1].getArgs.map (·.getId)
  let shells := stx[3].getArgs.map (·.getId)
  let env ← getEnv
  let verified (m : Name) := pfxs.any (·.isPrefixOf m)
  let mut bad := #[]
  let mut nThm := 0
  let mut nDef := 0
  for (n, ci) in env.constants.toList do
    let some m := moduleOf env n | continue
    unless verified m do continue
    if n.isInternalDetail || (`ctorIdx).isSuffixOf n then continue
    if ci.isUnsafe then bad := bad.push s!"unsafe: {n}"
    if ci matches .opaqueInfo _ then bad := bad.push s!"opaque/partial: {n}"
    if isExtern env n then bad := bad.push s!"extern: {n}"
    if (Compiler.implementedByAttr.getParam? env n).isSome then bad := bad.push s!"implemented_by: {n}"
    -- Theorems *and* definitions: a definition no theorem uses (say, a helper only the shell
    -- calls) could otherwise hide `sorry` or `native_decide` (`Lean.ofReduceBool`).
    if ci matches .thmInfo _ || ci matches .defnInfo _ then
      if ci matches .thmInfo _ then nThm := nThm + 1 else nDef := nDef + 1
      for a in ← liftCoreM (collectAxioms n) do
        unless standardAxioms.contains a do bad := bad.push s!"axiom {a} used by {n}"
  -- Stage 6, "leaves made opaque": verified code must not depend, through helpers outside the
  -- verified modules, on a constant whose compiled code differs from the body the kernel checks:
  -- `@[implemented_by]`, or `@[extern]` on a definition that has a body. An `@[extern] opaque`
  -- leaf is fine, since no proof can see its behaviour. The core library (Init, Std, Lean) is the
  -- trusted base and is not walked.
  let core (m : Name) := [`Init, `Std, `Lean, `Lake].any (·.isPrefixOf m)
  let mut seen : NameSet := {}
  let mut todo : Array Name := #[]
  for (n, ci) in env.constants.toList do
    if let some m := moduleOf env n then
      if verified m && !n.isInternalDetail then todo := todo ++ ci.getUsedConstantsAsSet.toList.toArray
  while todo.size > 0 do
    let c := todo.back!
    todo := todo.pop
    if seen.contains c then continue
    seen := seen.insert c
    let some m := moduleOf env c | continue
    if verified m || core m then continue
    -- compiler-generated (`ctorIdx` is `@[implemented_by]` by construction), as in the loop above
    if c.isInternalDetail || (`ctorIdx).isSuffixOf c then continue
    let some ci := env.find? c | continue
    if (Compiler.implementedByAttr.getParam? env c).isSome then
      bad := bad.push s!"verified code depends on {c}, which is @[implemented_by]: the proofs check its body, the program runs other code"
    else if isExtern env c && ci matches .defnInfo _ then
      bad := bad.push s!"verified code depends on {c}, an @[extern] with a body: the proofs check the body, the program runs the external code"
    todo := todo ++ ci.getUsedConstantsAsSet.toList.toArray
  for i in [0:env.header.moduleNames.size] do
    let m := env.header.moduleNames[i]!
    if verified m then
      for imp in env.header.moduleData[i]!.imports do
        if shells.any (·.isPrefixOf imp.module) then bad := bad.push s!"{m} imports {imp.module}"
  -- an audit that sees nothing proves nothing (a misspelt prefix, a module not imported)
  if nThm + nDef == 0 then
    bad := bad.push s!"no theorems or definitions found under {pfxs.toList} (misspelt, or not imported?)"
  if bad.isEmpty then
    logInfo m!"Verified-code audit: OK ({nThm} theorems and {nDef} definitions on standard axioms; no unsafe/partial/opaque/implemented_by/extern; {shells.toList} not imported)"
  else throwError m!"Verified-code audit FAILED:\n{"\n".intercalate (bad.qsort (· < ·)).toList}"

syntax (name := assertShellCalls) "#assert_shell_calls " ident " within " ident " (" ident* ")" : command

/-- `#assert_shell_calls main within Root (f g …)`: the trusted shell's entry point reaches every
listed verified function (for example the filled hole `CounterImpl.pick` and `LeanKV.Core.execPick`)
through code in modules under `Root`. Catches a shell that bypasses the verified core entirely;
it cannot show the shell uses the results correctly (that is what the CLI tests are for). -/
@[command_elab assertShellCalls] def elabAssertShellCalls : CommandElab := fun stx => do
  let entry := stx[1].getId
  let root := stx[3].getId
  let want := stx[5].getArgs.map (·.getId)
  let env ← getEnv
  if (env.find? entry).isNone then throwError "Shell gate: entry point {entry} not found"
  let mut seen : Std.HashSet Name := {}
  let mut todo := [entry]
  while !todo.isEmpty do
    let n := todo.head!
    todo := todo.tail!
    if seen.contains n then continue
    seen := seen.insert n
    let inApp := match moduleOf env n with | some m => root.isPrefixOf m | none => n == entry
    unless inApp do continue
    if let some ci := env.find? n then
      if let some v := ci.value? then todo := v.getUsedConstants.toList ++ todo
  let missing := want.filter (!seen.contains ·)
  if missing.isEmpty then logInfo m!"Shell gate: OK ({entry} reaches {want.toList})"
  else throwError m!"Shell gate: {entry} never reaches {missing.toList} (the shell bypasses the verified code)"

end MakeItLean
