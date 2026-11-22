import Lean.Data.Json

/-!
# `mil` — the MakeItLean CLI

    mil init <AppName> <dir>          create an app from templates/app (spec + impl packages)
    mil solution <app>/mil.json       generate the comparator solution module from the hole files
    mil judge <app>/mil.json          build, then `lake comparator` from the root judge workspace
    mil freeze <app>/mil.json <who>   record the spec's file hashes in spec.lock (after sign-off)
    mil check-lock <app>/mil.json     verify the frozen spec is unchanged
    mil review <app>/mil.json         generate SPEC_REVIEW.md from the elaborated spec
    mil audit <app>/mil.json          lock, spec gates, comparator --paranoid, verified-code audit

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

def loadConfig (path : FilePath) : IO Config := do
  let j ← match Json.parse (← IO.FS.readFile path) with
    | .ok j => pure j | .error e => die s!"{path}: {e}"
  return { specModule := ← getStr j "spec_module", holeFiles := ← getList j "hole_files",
           implDir := ← getStr j "impl_dir", solutionModule := ← getStr j "solution_module",
           solutionImports := ← getList j "solution_imports", holes := ← getMap j "holes",
           obligations := ← getMap j "obligations", lockFiles := ← getList j "lock_files" }

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

/-- `mil judge`: generate the solution, build, and run the comparator from the judge workspace. -/
def judge (cfgPath : FilePath) (paranoid : Bool) : IO Unit := do
  let cfg ← loadConfig cfgPath
  let base ← IO.FS.realPath (cfgPath.parent.getD ".")
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

/-- `mil init`: copy templates/app into `dir`, renaming `App`/`app` to the new name. -/
def init (name dir : String) : IO Unit := do
  let root ← findRoot (← IO.currentDir)
  let tmpl := root / "templates" / "app"
  if ← (FilePath.mk dir).pathExists then die s!"{dir} already exists"
  run "cp" #["-r", tmpl.toString, dir]
  let files := (← capture "find" #[dir, "-type", "f"]).splitOn "\n" |>.filter (· != "")
  let lower := name.decapitalize
  for f in files do
    let s ← IO.FS.readFile f
    IO.FS.writeFile f ((s.replace "AppName" name).replace "appname" lower)
  for d in (← capture "find" #[dir, "-depth", "-name", "*AppName*"]).splitOn "\n" |>.filter (· != "") do
    run "mv" #[d, d.replace "AppName" name]
  -- register the app's implementation in the root judge workspace (its sandbox must see it)
  let rootLake := root / "lakefile.lean"
  let absDir ← IO.FS.realPath dir
  let rel := (absDir.toString.drop (root.toString.length + 1)).toString
  IO.FS.writeFile rootLake ((← IO.FS.readFile rootLake) ++ s!"require {lower}Impl from \"{rel}/impl\"\n")
  run "lake" #["update", s!"{lower}Impl"] root
  IO.println s!"created {dir} (spec package; implementation in {dir}/impl), registered in the judge workspace. Next: write REQUIREMENTS.md (Stage 0)."

/-- `mil audit`: lock (if frozen), spec gates, comparator (--paranoid), verified-code audit. -/
def audit (cfgPath : FilePath) : IO Unit := do
  let cfg ← loadConfig cfgPath
  let base := cfgPath.parent.getD "."
  if ← (base / "spec.lock").pathExists then checkLock cfgPath
  else IO.println "spec not frozen yet (no spec.lock)"
  IO.println "== spec gates"; run "lake" #["build"] base
  IO.println "== comparator (--paranoid)"; judge cfgPath true
  IO.println "== verified-code audit"; run "lake" #["env", "lean", "audit.lean"] (base / cfg.implDir)
  IO.println "AUDIT PASSED"

def usage : String := "usage: mil init <AppName> <dir> | solution|judge|check-lock|review|audit <mil.json> | freeze <mil.json> <who> | judge --paranoid <mil.json>"

def main (args : List String) : IO UInt32 := do
  try
    match args with
    | ["init", n, d] => init n d
    | ["solution", c] => solution c
    | ["judge", c] => judge c false
    | ["judge", "--paranoid", c] => judge c true
    | ["freeze", c, who] => freeze c who
    | ["check-lock", c] => checkLock c
    | ["review", c] => review c
    | ["audit", c] => audit c
    | _ => IO.eprintln usage; return 2
    return 0
  catch e => IO.eprintln s!"mil: {e}"; return 1

end Mil

def main (args : List String) : IO UInt32 := Mil.main args
