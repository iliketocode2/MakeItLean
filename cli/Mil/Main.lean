import Lean.Data.Json

/-!
# `mil` — the MakeItLean CLI

    mil init [--pure] <AppName> <dir> create an app from templates/app (on the LeanKV substrate)
                                      or templates/pure (one pure function)
    mil solution <app>/mil.json       generate the comparator solution module from the hole files
    mil judge <app>/mil.json          build, then `lake comparator` from the root judge workspace
    mil freeze <app>/mil.json <who>   record the spec's file hashes in spec.lock (after sign-off)
    mil check-lock <app>/mil.json     verify the frozen spec is unchanged
    mil review <app>/mil.json         generate SPEC_REVIEW.md from the elaborated spec
    mil contract <app>/mil.json       the spec's holes and obligations are exactly mil.json's
    mil audit <app>/mil.json          lock (required), spec gates, contract, comparator --paranoid,
                                      verified-code audit (`--allow-unfrozen` for development runs)

Every path in `mil.json` is relative to the directory holding it (the app's spec package).
-/

open Lean System

namespace Mil

/-- Per-app configuration (`mil.json`). -/
structure Config where
  /-- Spec aggregator module, e.g. `Counter.Spec` (the comparator's challenge). -/
  specModule : String
  /-- Spec files holding implementation holes and their obligations. -/
  holeFiles : List String
  /-- Implementation package directory, relative to the spec package. -/
  implDir : String
  /-- Generated solution module, e.g. `CounterSol.Holes`. -/
  solutionModule : String
  /-- Modules the solution imports (the implementation and its proofs). -/
  solutionImports : List String
  /-- Fully qualified hole names → the term filling each (`Impl.pick` → `CounterImpl.pick`). -/
  holes : List (String × String)
  /-- Fully qualified obligation names → the proof term of each. -/
  obligations : List (String × String)
  /-- Spec files hashed into `spec.lock` (besides the lakefile and toolchain). -/
  lockFiles : List String
  /-- A pure-function app (`"kind": "pure"`): no storage substrate and no shell. -/
  pure : Bool := false
  deriving Inhabited

def die {α} (msg : String) : IO α := throw (IO.userError msg)

def getStr (j : Json) (k : String) : IO String :=
  match j.getObjValAs? String k with | .ok s => pure s | .error e => die s!"mil.json: {k}: {e}"

def getList (j : Json) (k : String) : IO (List String) :=
  match j.getObjValAs? (Array String) k with | .ok a => pure a.toList | .error e => die s!"mil.json: {k}: {e}"

def getMap (j : Json) (k : String) : IO (List (String × String)) := do
  let some (.obj o) := (j.getObjVal? k).toOption | die s!"mil.json: {k}: expected an object"
  o.toList.mapM fun (n, v) => match v.getStr? with
    | .ok s => pure (n, s) | .error e => die s!"mil.json: {k}.{n}: {e}"

/-- Hole or obligation fills. New format: `mil.json` lists the names (an array, part of the frozen
spec) and the implementation's `fill.json` maps each name to its term, so filling them after the
freeze does not touch a locked file. Legacy format: an object of name → term inside `mil.json`. -/
def getFills (j : Json) (k : String) (fill : Option Json) (fillPath : FilePath) : IO (List (String × String)) := do
  match j.getObjVal? k with
  | .ok (.obj _) => getMap j k
  | .ok (.arr a) =>
    a.toList.mapM fun v => do
      let some n := v.getStr?.toOption | die s!"mil.json: {k}: expected names"
      let some f := fill | die s!"{fillPath} is missing: it maps each hole and obligation to its term"
      let some m := (f.getObjVal? k).toOption | die s!"{fillPath}: missing \"{k}\""
      match m.getObjValAs? String n with
      | .ok t => pure (n, t)
      | .error _ => die s!"{fillPath}: {k}.{n}: no term"
  | _ => die s!"mil.json: {k}: expected an array of names (or a legacy object)"

def loadConfig (path : FilePath) : IO Config := do
  let j ← match Json.parse (← IO.FS.readFile path) with
    | .ok j => pure j | .error e => die s!"{path}: {e}"
  let implDir ← getStr j "impl_dir"
  let fillPath := (path.parent.getD ".") / implDir / "fill.json"
  let fill ← if ← fillPath.pathExists then
      match Json.parse (← IO.FS.readFile fillPath) with
      | .ok f => pure (some f) | .error e => die s!"{fillPath}: {e}"
    else pure none
  return { specModule := ← getStr j "spec_module", holeFiles := ← getList j "hole_files",
           implDir, solutionModule := ← getStr j "solution_module",
           solutionImports := ← getList j "solution_imports",
           holes := ← getFills j "holes" fill fillPath,
           obligations := ← getFills j "obligations" fill fillPath, lockFiles := ← getList j "lock_files",
           pure := (j.getObjValAs? String "kind").toOption == some "pure" }

/-- Run a command, streaming its output; fail if it fails. -/
def run (cmd : String) (args : Array String) (cwd : Option FilePath := none) : IO Unit := do
  let child ← IO.Process.spawn { cmd, args, cwd }
  let rc ← child.wait
  unless rc == 0 do die s!"`{cmd} {" ".intercalate args.toList}` failed (exit {rc})"

/-- Run a command and capture stdout. -/
def capture (cmd : String) (args : Array String) (cwd : Option FilePath := none) : IO String := do
  let out ← IO.Process.output { cmd, args, cwd }
  unless out.exitCode == 0 do die s!"`{cmd}` failed: {out.stderr}"
  return out.stdout

/-- The last component of a dotted name: `Counter.Spec.Impl.pick` ↦ `Impl.pick`, matching how
the declaration is written inside its `namespace`. -/
def shortName (full : String) (ns : String) : String :=
  if full.startsWith (ns ++ ".") then (full.drop (ns.length + 1)).toString else full

/-- Replace the body `sorry` of declaration `decl` (the first `sorry` after its name). -/
def fillSorry (src decl term : String) : IO String := do
  let keys := [s!" {decl} ", s!" {decl}\n"]
  let some key := keys.find? (fun k => (src.splitOn k).length == 2)
    | die s!"hole file: declaration `{decl}` not found exactly once"
  match src.splitOn key with
  | [before, after] =>
    match after.splitOn "sorry" with
    | hd :: tl@(_ :: _) => return before ++ key ++ hd ++ term ++ "sorry".intercalate tl
    | _ => die s!"no `sorry` after `{decl}`"
  | _ => die "unreachable"

/-- `mil solution`: the hole files, verbatim, with every hole and obligation filled. -/
def solution (cfgPath : FilePath) : IO Unit := do
  let cfg ← loadConfig cfgPath
  let base := cfgPath.parent.getD "."
  let mut body := ""
  for f in cfg.holeFiles do
    let mut src ← IO.FS.readFile (base / f)
    let ns := ((src.splitOn "\nnamespace ").drop 1).head?.map (·.takeWhile (· != '\n') |>.toString) |>.getD ""
    for (n, t) in cfg.holes ++ cfg.obligations do
      if (src.splitOn s!" {shortName n ns}").length > 1 then
        src ← fillSorry src (shortName n ns) t
    body := body ++ s!"\n-- from {f}\n" ++ src
  let header := "-- GENERATED by `mil solution` from the frozen hole files. Do not edit.\n" ++
    String.join (cfg.solutionImports.map (s!"import {·}\n"))
  -- imports must come first: hoist the hole files' own imports
  let lines := body.splitOn "\n"
  let imports := lines.filter (·.startsWith "import ")
  let rest := lines.filter (fun l => !l.startsWith "import ")
  let out := header ++ String.join (imports.map (· ++ "\n")) ++ "\n".intercalate rest
  let path := base / cfg.implDir / ((cfg.solutionModule.replace "." "/") ++ ".lean")
  IO.FS.createDirAll (path.parent.getD ".")
  IO.FS.writeFile path out
  let remaining := (out.splitOn ":= sorry").length - 1
  IO.println s!"wrote {path} ({cfg.holes.length} holes, {cfg.obligations.length} obligations; `:= sorry` left: {remaining})"

/-- The repository root (the judge workspace): the nearest ancestor holding `judge/`. -/
partial def findRoot (d : FilePath) : IO FilePath := do
  if ← (d / "judge").isDir then return d
  match d.parent with
  | some p => if p == d then die "no judge workspace found" else findRoot p
  | none => die "no judge workspace found (a directory with judge/ above the app)"

/-- The contract gate: the elaborated spec's holes and obligations are exactly `mil.json`'s, so no
theorem escapes the comparator by naming a hole without being listed. -/
def contract (cfgPath : FilePath) : IO Unit := do
  let cfg ← loadConfig cfgPath
  let base := cfgPath.parent.getD "."
  let names (l : List (String × String)) := " ".intercalate (l.map (·.1))
  let file := base / ".mil_contract.lean"
  IO.FS.writeFile file s!"import {cfg.specModule}\nimport MakeItLean.Gates\n#assert_contract {cfg.specModule} ({names cfg.holes}) ({names cfg.obligations})\n"
  try run "lake" #["env", "lean", ".mil_contract.lean"] base
  finally IO.FS.removeFile file

/-- `mil judge`: generate the solution, build, and run the comparator from the judge workspace. -/
def judge (cfgPath : FilePath) (paranoid : Bool) : IO Unit := do
  let cfg ← loadConfig cfgPath
  let base ← IO.FS.realPath (cfgPath.parent.getD ".")
  run "lake" #["build"] base
  contract cfgPath
  solution cfgPath
  run "lake" #["build"] (base / cfg.implDir)
  let root ← findRoot base
  let name := cfg.specModule.replace "." "_"
  let judgeCfg := Json.mkObj [
    ("challenge_module", cfg.specModule), ("solution_module", cfg.solutionModule),
    ("theorem_names", toJson (cfg.obligations.map (·.1))),
    ("definition_names", toJson (cfg.holes.map (·.1))),
    ("permitted_axioms", toJson ["propext", "Quot.sound", "Classical.choice"])]
  IO.FS.writeFile (root / "judge" / s!"{name}.json") judgeCfg.pretty
  run "lake" #["build", cfg.specModule, cfg.solutionModule] root
  let args := #["comparator", s!"--config=judge/{name}.json"] ++ (if paranoid then #["--paranoid"] else #[])
  let out ← IO.Process.output { cmd := "lake", args, cwd := root }
  let errs := (out.stdout.splitOn "\n").filter (·.startsWith "error")
  if out.exitCode == 0 then IO.println "ACCEPTED: all obligations proven against the spec"
  else die ("REJECTED:\n" ++ "\n".intercalate errs)

/-- Files covered by the lock. -/
def lockList (cfg : Config) : List String := ["lean-toolchain", "lakefile.lean", "mil.json"] ++ cfg.lockFiles

/-- `mil freeze`: write spec.lock (refuses if one exists). -/
def freeze (cfgPath : FilePath) (who : String) : IO Unit := do
  let cfg ← loadConfig cfgPath
  let base := cfgPath.parent.getD "."
  if ← (base / "spec.lock").pathExists then die "spec.lock exists: the spec is frozen; changes need a new sign-off"
  run "lake" #["build"] base
  let sums ← capture "sha256sum" (lockList cfg).toArray base
  IO.FS.writeFile (base / "spec.lock") s!"# Frozen spec. Signed off by: {who}\n{sums}"
  IO.println s!"Frozen ({(lockList cfg).length} files)."

/-- `mil check-lock`: the frozen files are byte-for-byte what was signed off. -/
def checkLock (cfgPath : FilePath) : IO Unit := do
  let base := cfgPath.parent.getD "."
  let lock ← IO.FS.readFile (base / "spec.lock")
  let body := "\n".intercalate (lock.splitOn "\n" |>.filter (!·.startsWith "#"))
  let spawnArgs : IO.Process.SpawnArgs :=
    { cmd := "sha256sum", args := #["--check", "--quiet"], cwd := some base, stdin := .piped }
  let child ← IO.Process.spawn spawnArgs
  let (stdin, child) ← child.takeStdin
  stdin.putStr body; stdin.flush
  let rc ← child.wait
  if rc == 0 then IO.println "spec.lock OK" else die "spec.lock MISMATCH: the frozen spec was changed"

/-- `mil review`: SPEC_REVIEW.md generated from the elaborated spec (`#spec_review`). -/
def review (cfgPath : FilePath) : IO Unit := do
  let cfg ← loadConfig cfgPath
  let base := cfgPath.parent.getD "."
  let pfx := cfg.specModule
  IO.FS.writeFile (base / ".mil_review.lean") s!"import {pfx}\nimport MakeItLean.Review\n#spec_review {pfx} \"SPEC_REVIEW.md\"\n"
  run "lake" #["env", "lean", ".mil_review.lean"] base
  IO.FS.removeFile (base / ".mil_review.lean")
  -- The evidence a reviewer most wants: the executable examples and the spec critic's checks.
  -- Shown verbatim from source; each line is checked by `lake build` (a failing `#guard` fails it).
  let guards (f : FilePath) : IO (List String) := do
    -- each `#guard` with its indented continuation lines, and the `-- ` comments that label them
    let (out, _) := ((← IO.FS.readFile f).splitOn "\n").foldl (init := (([] : List String), false))
      fun (acc, inGuard) l =>
        if l.startsWith "#guard" then (l :: acc, true)
        else if inGuard && l.startsWith " " then (l :: acc, true)
        else if l.startsWith "-- " then (l :: acc, false)
        else (acc, false)
    return out.reverse
  let mut extra := "\n## Executable examples (`#guard`, checked at build time)\n"
  for f in cfg.lockFiles.filter (·.endsWith ".lean") do
    let ls ← guards (base / f)
    if ls.any (·.startsWith "#guard") then
      extra := extra ++ s!"\n### `{f}`\n\n```lean\n" ++ "\n".intercalate ls ++ "\n```\n"
  let critic := base / ((pfx.takeWhile (· != '.')).toString) / "SpecCritic"
  if ← critic.isDir then
    extra := extra ++ "\n## Spec critic (wrong implementations and models the spec must reject)\n"
    for e in ← critic.readDir do
      if e.path.extension == some "lean" then
        extra := extra ++ s!"\n### `{e.fileName}`\n\n```lean\n" ++ "\n".intercalate (← guards e.path) ++ "\n```\n"
  else extra := extra ++ "\n## Spec critic\n\nNo `SpecCritic/` directory: the spec critic's checks are missing.\n"
  IO.FS.writeFile (base / "SPEC_REVIEW.md") ((← IO.FS.readFile (base / "SPEC_REVIEW.md")) ++ extra)

/-- `mil init [--pure]`: copy templates/app (an app on the LeanKV substrate) or templates/pure (a
pure function) into `dir`, renaming `AppName`/`appname` to the new name and `MIL_ROOT` to the
relative path from the app to the repository root. -/
def init (name dir : String) (pure : Bool := false) : IO Unit := do
  let root ← findRoot (← IO.currentDir)
  let tmpl := root / "templates" / (if pure then "pure" else "app")
  if ← (FilePath.mk dir).pathExists then die s!"{dir} already exists"
  IO.FS.createDirAll ((FilePath.mk dir).parent.getD ".")
  run "cp" #["-r", tmpl.toString, dir]
  let absDir ← IO.FS.realPath dir
  let rel := (absDir.toString.drop (root.toString.length + 1)).toString
  let up := "/".intercalate ((rel.splitOn "/").map fun _ => "..")
  let files := (← capture "find" #[dir, "-type", "f"]).splitOn "\n" |>.filter (· != "")
  let lower := name.decapitalize
  for f in files do
    let s ← IO.FS.readFile f
    IO.FS.writeFile f (((s.replace "AppName" name).replace "appname" lower).replace "MIL_ROOT" up)
  for d in (← capture "find" #[dir, "-depth", "-name", "*AppName*"]).splitOn "\n" |>.filter (· != "") do
    run "mv" #[d, d.replace "AppName" name]
  -- register the app's implementation in the root judge workspace (its sandbox must see it)
  let rootLake := root / "lakefile.lean"
  IO.FS.writeFile rootLake ((← IO.FS.readFile rootLake) ++ s!"require {lower}Impl from \"{rel}/impl\"\n")
  run "lake" #["update", s!"{lower}Impl"] root
  IO.println s!"created {dir} (spec package; implementation in {dir}/impl), registered in the judge workspace. Next: write REQUIREMENTS.md (Stage 0)."

/-- Module name of a source path: `Ledger/Spec/Model.lean` ↦ `Ledger.Spec.Model`. -/
def moduleOfPath (p : String) : String := ((p.take (p.length - 5)).toString).replace "/" "."

/-- The trust and shell gates: `TRUST.md` exists and every Lean name it cites exists; the shell's
`main` reaches the verified `pick` and `execPick`. The names are looked up
in the implementation, its proofs, the shell, the solution and the spec's hole-free modules. -/
def trust (cfg : Config) (base : FilePath) : IO Unit := do
  let impl := base / cfg.implDir
  let root := (cfg.solutionImports.head?.getD "").takeWhile (· != '.') |>.toString
  let shell := root ++ ".Shell"
  let shellOk := !cfg.pure &&
    (← IO.Process.output { cmd := "lake", args := #["build", shell], cwd := impl }).exitCode == 0
  unless cfg.pure || shellOk do die s!"cannot build the shell module {shell} (the CLI entry point the audit checks)"
  let specFile := (cfg.specModule.replace "." "/") ++ ".lean"
  let specMods := (cfg.lockFiles.filter fun f => f.endsWith ".lean" && !cfg.holeFiles.contains f && f != specFile).map moduleOfPath
  let mods := cfg.solutionImports ++ [cfg.solutionModule] ++ (if shellOk then [shell] else []) ++ specMods ++ ["MakeItLean.Gates"]
  let absBase ← IO.FS.realPath base
  let fills := (cfg.holes.map (·.2)).filter (fun t => !t.any (· == ' '))
  let file := impl / ".mil_trust.lean"
  IO.FS.writeFile file (String.join (mods.map (s!"import {·}\n")) ++
    s!"#assert_trust_cites \"{absBase / "TRUST.md"}\" \"{absBase}\"\n" ++
    -- the shell must reach the filled holes (those filled by a plain name) and the substrate runner
    (if cfg.pure then "" else  -- a pure app has no shell
      s!"#assert_shell_calls main within {root} ({" ".intercalate (fills ++ ["LeanKV.Core.execPick"])})\n"))
  try run "lake" #["env", "lean", ".mil_trust.lean"] impl
  finally IO.FS.removeFile file

/-- `mil audit`: lock (required unless --allow-unfrozen), spec gates, contract, comparator
(--paranoid), verified-code audit, trust manifest. -/
def audit (cfgPath : FilePath) (allowUnfrozen : Bool) : IO Unit := do
  let cfg ← loadConfig cfgPath
  let base := cfgPath.parent.getD "."
  if ← (base / "spec.lock").pathExists then checkLock cfgPath
  else if allowUnfrozen then IO.println "WARNING: spec not frozen (no spec.lock); this audit is not a release check"
  else die "no spec.lock: the spec was never frozen. Freeze it after sign-off (`mil freeze`), or pass --allow-unfrozen for a development run"
  IO.println "== spec gates"; run "lake" #["build"] base
  IO.println "== comparator (--paranoid)"; judge cfgPath true
  IO.println "== verified-code audit"; run "lake" #["env", "lean", "audit.lean"] (base / cfg.implDir)
  IO.println "== trust manifest and shell wiring"; trust cfg base
  IO.println (if ← (base / "spec.lock").pathExists then "AUDIT PASSED" else "AUDIT PASSED (UNFROZEN SPEC)")

def usage : String := "usage: mil init [--pure] <AppName> <dir> | solution|judge|contract|check-lock|review|audit <mil.json> | freeze <mil.json> <who> | judge --paranoid <mil.json> | audit --allow-unfrozen <mil.json>"

def main (args : List String) : IO UInt32 := do
  try
    match args with
    | ["init", n, d] => init n d
    | ["init", "--pure", n, d] => init n d true
    | ["solution", c] => solution c
    | ["judge", c] => judge c false
    | ["judge", "--paranoid", c] => judge c true
    | ["freeze", c, who] => freeze c who
    | ["check-lock", c] => checkLock c
    | ["review", c] => review c
    | ["audit", c] => audit c false
    | ["audit", "--allow-unfrozen", c] => audit c true
    | ["contract", c] => contract c
    | _ => IO.eprintln usage; return 2
    return 0
  catch e => IO.eprintln s!"mil: {e}"; return 1

end Mil

def main (args : List String) : IO UInt32 := Mil.main args
