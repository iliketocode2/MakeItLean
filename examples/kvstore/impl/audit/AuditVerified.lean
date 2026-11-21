import Lean
import LeanKVImpl.Core
import LeanKVImpl.Proofs
import LeanKVSol.Holes

/-!
# Stage 6 audit of the verified modules

For every declaration in the verified modules (`LeanKVImpl.Core*`, `LeanKVImpl.Proofs*`,
`LeanKVSol*`), check on the *compiled environment* (not source text):
- theorems use only `propext`, `Quot.sound`, `Classical.choice` (so no `sorry`, no custom axiom,
  no `native_decide`/`bv_decide` whose proofs use `Lean.ofReduceBool`);
- no declarations are `unsafe`, `partial` or `opaque`, and none carry `@[implemented_by]` or `@[extern]`;
- no verified module imports the trusted shell (`LeanKVImpl.Shell*`).
Run: `lake env lean audit/AuditVerified.lean` (fails with an error on any violation).
-/

open Lean Elab Command

def verifiedPrefixes : List Name := [`LeanKVImpl.Core, `LeanKVImpl.Proofs, `LeanKVSol]
def permitted : List Name := [``propext, ``Quot.sound, ``Classical.choice]

elab "#audit_verified" : command => do
  let env ← getEnv
  let isVerified (mod : Name) := verifiedPrefixes.any (·.isPrefixOf mod)
  let mut bad : Array String := #[]
  let mut nThm := 0
  let mut nDef := 0
  for (n, ci) in env.constants.toList do
    let some idx := env.getModuleIdxFor? n | continue
    let some mod := env.header.moduleNames[idx.toNat]? | continue
    unless isVerified mod do continue
    -- compiler-generated helpers (`_unsafe_rec`, `ctorIdx`, …) are not user code; a user
    -- `partial def f` still shows up as `f` carrying `implemented_by`, which is checked below
    if n.isInternalDetail || (`ctorIdx).isSuffixOf n then continue
    if ci.isUnsafe then bad := bad.push s!"unsafe: {n}"
    -- `partial def` (and `opaque`) compile to opaque constants whose bodies proofs cannot see
    if ci matches .opaqueInfo _ then bad := bad.push s!"opaque/partial: {n}"
    if isExtern env n then bad := bad.push s!"extern: {n}"
    if (Compiler.implementedByAttr.getParam? env n).isSome then bad := bad.push s!"implemented_by: {n}"
    if let .defnInfo d := ci then
      nDef := nDef + 1
      if d.safety == .partial then bad := bad.push s!"partial: {n}"
    if ci matches .thmInfo _ then
      nThm := nThm + 1
      let axs ← liftCoreM (collectAxioms n)
      for a in axs do
        unless permitted.contains a do bad := bad.push s!"axiom {a} used by {n}"
  -- the trusted shell must not leak into verified modules
  for mod in env.header.moduleNames, i in [0:env.header.moduleNames.size] do
    if isVerified mod then
      for imp in env.header.moduleData[i]!.imports do
        if (`LeanKVImpl.Shell).isPrefixOf imp.module then
          bad := bad.push s!"verified module {mod} imports shell module {imp.module}"
  if bad.isEmpty then
    logInfo m!"AUDIT OK: {nThm} theorems use only propext/Quot.sound/Classical.choice; {nDef} definitions; no unsafe/partial/opaque/implemented_by/extern; shell not imported by verified modules"
  else
    throwError m!"AUDIT FAILED ({bad.size}):\n{"\n".intercalate bad.toList}"

#audit_verified
