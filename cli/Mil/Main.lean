import Lean.Data.Json

/-!
# `mil` — the MakeItLean CLI

    mil init [--pure] [--agent claude|codex] <AppName> <dir>
                                      create an app from templates/app (on the LeanKV substrate)
                                      or templates/pure (one pure function)
    mil solution <app>/mil.json       generate the comparator solution module from the hole files
    mil judge <app>/mil.json          build, then `lake comparator` in a staged judge workspace
                                      (a temporary copy of only this app's packages)
    mil comparator [--paranoid] <impl_dir> <config.json>
                                      the staged comparator for a built package with its own config
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

/-- A substrate app's end-to-end facts, which the generated audit pins to the frozen spec's `dec`,
`cstep`, `pickRef` and `toBytes` (names fully qualified). -/
structure SubstrateCfg where
  /-- The model's state type, e.g. `Counter.Spec.CState`. -/
  state : String
  /-- The model's command type constructor (generic in the byte type), e.g. `Counter.Spec.CCmd`. -/
  cmd : String
  /-- The implementation's `pick`, e.g. `CounterImpl.pick`. -/
  pick : String
  /-- The theorem `PickOk pick …`, e.g. `CounterImpl.pickOk`. -/
  pickOk : String
  /-- The theorem `Refines dec … …`, e.g. `CounterImpl.refines`. -/
  refines : String
  /-- The end-to-end theorem `TRUST.md` cites, e.g. `CounterImpl.crash_consistent`. -/
  crashConsistent : String
  deriving Inhabited

/-- What the verified-code audit covers (`mil.json`'s `audit` object; locked at the freeze). `mil`
generates the audit from it, so the implementation cannot narrow or remove it. -/
structure AuditCfg where
  /-- Module prefixes of the verified code (the solution's root is always added). -/
  verified : List String
  /-- Module prefixes of the trusted shell, which verified code must not import. -/
  shell : List String
  /-- A substrate app's end-to-end facts; absent for a pure app. -/
  substrate : Option SubstrateCfg := none
  deriving Inhabited

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
  /-- The audit's coverage (`audit` in `mil.json`). Absent: a legacy app, whose own
  `impl/audit.lean` runs only if its hash is in the framework's `lean/legacy_audits.json`. -/
  audit : Option AuditCfg := none
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
  let audit ← match j.getObjVal? "audit" with
    | .error _ => Pure.pure none
    | .ok a => do
      let substrate ← match a.getObjVal? "substrate" with
        | .error _ => Pure.pure none
        | .ok s => Pure.pure (some {
            state := ← getStr s "state", cmd := ← getStr s "cmd", pick := ← getStr s "pick",
            pickOk := ← getStr s "pick_ok", refines := ← getStr s "refines",
            crashConsistent := ← getStr s "crash_consistent" : SubstrateCfg })
      Pure.pure (some { verified := ← getList a "verified", shell := ← getList a "shell", substrate : AuditCfg })
  let isPure := (j.getObjValAs? String "kind").toOption == some "pure"
  if let some a := audit then
    if a.verified.isEmpty then die "mil.json: audit.verified: list at least one verified module prefix"
    if !isPure && a.substrate.isNone then die "mil.json: audit.substrate: a substrate app must name its end-to-end facts"
  return { specModule := ← getStr j "spec_module", holeFiles := ← getList j "hole_files",
           implDir, solutionModule := ← getStr j "solution_module",
           solutionImports := ← getList j "solution_imports",
           holes := ← getFills j "holes" fill fillPath,
           obligations := ← getFills j "obligations" fill fillPath, lockFiles := ← getList j "lock_files",
           pure := isPure, audit }

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

/-- The MakeItLean checkout: the nearest ancestor holding `lean/MakeItLean/Gates.lean` (the same
marker the guard hooks use). Needed only by `mil init`, for the templates. -/
partial def findRoot (d : FilePath) : IO FilePath := do
  if ← (d / "lean" / "MakeItLean" / "Gates.lean").pathExists then return d
  match d.parent with
  | some p => if p == d then die "no MakeItLean checkout found" else findRoot p
  | none => die "no MakeItLean checkout found (a directory with lean/MakeItLean/Gates.lean above this one)"

/-- The path components of an absolute path. -/
def comps (p : FilePath) : List String := p.toString.splitOn "/" |>.filter (· != "")

/-- The path packages a Lake package depends on (transitively), from its `lake-manifest.json`, as
absolute paths. Git packages are skipped: Lake clones them into the package's own
`.lake/packages`, which the staged judge copies along and uses as its packages directory. -/
def pathPackages (pkg : FilePath) : IO (List FilePath) := do
  let j ← match Json.parse (← IO.FS.readFile (pkg / "lake-manifest.json")) with
    | .ok j => pure j | .error e => die s!"{pkg}/lake-manifest.json: {e}"
  let ps ← match j.getObjValAs? (Array Json) "packages" with
    | .ok a => pure a | .error e => die s!"{pkg}/lake-manifest.json: packages: {e}"
  let mut out := []
  for p in ps do
    let name := (p.getObjValAs? String "name").toOption.getD "?"
    match (p.getObjValAs? String "type").toOption with
    | some "path" =>
      let some d := (p.getObjValAs? String "dir").toOption | die s!"package `{name}`: no dir in the manifest"
      out := out ++ [← IO.FS.realPath (pkg / d)]
    | some "git" => pure ()  -- cloned under `pkg/.lake/packages`, which is copied with `pkg`
    | t => die s!"package `{name}`: unsupported dependency type {t}"
  return out

/-- The package name a lakefile declares (`package foo` or `package foo where`). -/
def packageName (lakefile : FilePath) : IO String := do
  let some n := ((← IO.FS.readFile lakefile).splitOn "\n").findSome? (fun l =>
      if l.startsWith "package " then some ((l.drop 8).takeWhile (· != ' ')).toString else none)
    | die s!"{lakefile}: no `package` line"
  return n

/-- Each package a `lake-manifest.json` resolves, with its identity: `path:<real path>` or
`git:<url>@<rev>/<subDir>`. Path packages are resolved against the manifest's directory. -/
def manifestIds (dir : FilePath) : IO (List (String × String)) := do
  let j ← match Json.parse (← IO.FS.readFile (dir / "lake-manifest.json")) with
    | .ok j => pure j | .error e => die s!"{dir}/lake-manifest.json: {e}"
  let ps ← match j.getObjValAs? (Array Json) "packages" with
    | .ok a => pure a | .error e => die s!"{dir}/lake-manifest.json: packages: {e}"
  ps.toList.mapM fun p => do
    let name := (p.getObjValAs? String "name").toOption.getD "?"
    let s (k : String) := (p.getObjValAs? String k).toOption.getD ""
    match s "type" with
    | "path" =>
      let d := dir / s "dir"
      unless ← d.pathExists do die s!"package `{name}`: directory {d} not found"
      pure (name, s!"path:{← IO.FS.realPath d}")
    | "git" => pure (name, s!"git:{s "url"}@{s "rev"}/{s "subDir"}")
    | t => die s!"package `{name}`: unsupported dependency type {t}"

/-- Top-level module roots the implementation package must not define: the framework's, the
substrate's and the spec's. A module of the same name would let the implementation replace them. -/
def reservedRoots (cfg : Config) : List String :=
  ["MakeItLean", "MakeItLeanTest", "LeanKV", "LeanKVImpl", "LeanKVSol", "Mil",
   (cfg.specModule.takeWhile (· != '.')).toString]

/-- The implementation builds against exactly the frozen spec's dependencies:
- its lakefile's only `require` is the spec package (`require <spec> from ".."`);
- it defines no module under a framework, substrate or spec root;
- its manifest resolves the spec package to the spec directory, and every other package to the
  same place (path) or commit (git) as the spec's manifest, and nothing else.
Otherwise an implementation could build the spec, the gates or the substrate from its own copy:
`spec.lock` covers files, not what they import. -/
def checkDeps (cfg : Config) (base : FilePath) : IO Unit := do
  let base ← IO.FS.realPath base
  let impl ← IO.FS.realPath (base / cfg.implDir)
  let specPkg ← packageName (base / "lakefile.lean")
  let want := s!"require {specPkg} from \"..\""
  let reqs := ((← IO.FS.readFile (impl / "lakefile.lean")).splitOn "\n").filterMap fun l =>
    let t := l.trimAscii.toString
    if t.startsWith "require " || t.startsWith "require\t" then some t else none
  unless reqs == [want] do
    die s!"dependency check: {impl}/lakefile.lean must require only the spec package (`{want}`); found {reqs}"
  for e in ← impl.readDir do
    let stem := (e.path.fileStem.getD e.fileName)
    if (reservedRoots cfg).contains stem then
      die s!"dependency check: {e.path} would define modules under `{stem}`, which belongs to the framework, the substrate or the spec"
  let spec ← manifestIds base
  let got ← manifestIds impl
  let expected := (specPkg, s!"path:{base}") :: spec
  let fmt (l : List (String × String)) := l.map (fun (n, i) => s!"{n} ({i})")
  let missing := expected.filter (!got.contains ·)
  let extra := got.filter (!expected.contains ·)
  unless missing.isEmpty && extra.isEmpty do
    die s!"dependency check: the implementation's dependencies differ from the frozen spec's (run `lake update` in {impl} after restoring its lakefile).\n  expected but missing: {fmt missing}\n  unexpected: {fmt extra}"

/-- Run `lake comparator` on a built implementation package in a **staged judge workspace**: a
fresh temporary directory holding copies (sources and prebuilt `.lake`) of only the packages this
implementation needs, at their paths relative to their common ancestor. Locked relative `require`s
resolve unchanged, the comparator's sandbox sees only these copies, and judge runs share nothing,
so they can run in parallel. `MIL_KEEP_JUDGE=1` keeps the directory for inspection. -/
def stagedComparator (implDir : FilePath) (judgeCfg : Json) (paranoid : Bool) : IO Unit := do
  let impl ← IO.FS.realPath implDir
  let pkgs := impl :: (← pathPackages impl)
  -- the common ancestor of every package
  let cs := pkgs.map comps
  let common0 := (cs.head!.zip (List.range cs.head!.length)).takeWhile (fun (c, i) =>
    cs.all fun l => l[i]? == some c) |>.map (·.1)
  -- if a package *is* the common ancestor (LeanKV: `impl/` and its parent), go one level up, so
  -- every package keeps a non-empty relative path
  let common := if cs.any (·.length == common0.length) then common0.dropLast else common0
  let rel (p : FilePath) : String := "/".intercalate ((comps p).drop common.length)
  -- copy only outermost packages (a nested one, e.g. `impl/` under its spec package, comes along)
  let isUnder (a b : FilePath) : Bool := a != b && (comps b).isPrefixOf (comps a)
  let tops := (pkgs.eraseDups).filter fun p => !pkgs.any (isUnder p ·)
  let stage : FilePath := (← capture "mktemp" #["-d", "-t", "mil-judge-XXXXXX"]).trimAscii.toString
  try
    for p in tops do
      let dst := stage / rel p
      IO.FS.createDirAll (dst.parent.getD stage)
      run "cp" #["-a", p.toString, dst.toString]
    let tc := impl / "lean-toolchain"
    if ← tc.pathExists then IO.FS.writeFile (stage / "lean-toolchain") (← IO.FS.readFile tc)
    let implLake ← IO.FS.readFile (impl / "lakefile.lean")
    let some pkgName := (implLake.splitOn "\n").findSome? (fun l =>
        if l.startsWith "package " then some ((l.drop 8).takeWhile (· != ' ')).toString else none)
      | die s!"{impl}/lakefile.lean: no `package` line"
    -- the implementation's packages directory (where its git dependencies are cloned), as staged
    let pkgsDir ← do
      let j ← IO.ofExcept (Json.parse (← IO.FS.readFile (impl / "lake-manifest.json")))
      let d := (j.getObjValAs? String "packagesDir").toOption.getD ".lake/packages"
      let abs := impl / d
      if ← abs.pathExists then pure (rel (← IO.FS.realPath abs)) else pure (rel impl ++ "/" ++ d)
    IO.FS.writeFile (stage / "lakefile.lean")
      s!"import Lake\nopen Lake DSL\n\n/-! Staged judge workspace, generated by `mil`. Git dependencies are the implementation's own clones. -/\npackage milJudge where\n  packagesDir := \"{pkgsDir}\"\n\nrequire {pkgName} from \"{rel impl}\"\n"
    IO.FS.writeFile (stage / "judge.json") judgeCfg.pretty
    let quiet (args : Array String) : IO Unit := do
      let out ← IO.Process.output { cmd := "lake", args, cwd := stage }
      unless out.exitCode == 0 do die s!"staged judge: `lake {" ".intercalate args.toList}` failed:\n{out.stdout}{out.stderr}"
    quiet #["update"]
    -- `lake update` resolved the staged lakefiles afresh: every package must be the staged copy
    -- of what the implementation's manifest resolved (or the same git commit), and nothing else
    let implIds ← manifestIds impl
    let stageReal ← IO.FS.realPath stage
    let restage (id : String) : String :=
      if id.startsWith "path:" then s!"path:{stageReal}/{rel ⟨(id.drop 5).toString⟩}" else id
    let expected := (pkgName, s!"path:{stageReal}/{rel impl}") :: implIds.map (fun (n, i) => (n, restage i))
    let staged ← manifestIds stage
    let odd := staged.filter (!expected.contains ·)
    unless odd.isEmpty && staged.length == expected.length do
      die s!"staged judge: the staged workspace resolved packages other than the implementation's: {odd.map (fun (n, i) => s!"{n} ({i})")}"
    let mods := ["challenge_module", "solution_module"].filterMap (judgeCfg.getObjValAs? String · |>.toOption)
    quiet (#["build"] ++ mods.toArray)
    let args := #["comparator", "--config=judge.json"] ++ (if paranoid then #["--paranoid"] else #[])
    let out ← IO.Process.output { cmd := "lake", args, cwd := stage }
    let errs := ((out.stdout ++ out.stderr).splitOn "\n").filter (·.startsWith "error")
    if out.exitCode == 0 then IO.println "ACCEPTED: all obligations proven against the spec"
    else if errs.isEmpty then
      -- no verdict lines: usually the sandbox or the environment, not the proofs (Experiment B:
      -- bubblewrap blocked inside Codex's sandbox printed only a generic child failure)
      let lines := ((out.stdout ++ out.stderr).splitOn "\n").filter (!·.isEmpty)
      die ("REJECTED (no error lines: check the environment, e.g. bubblewrap; MIL_KEEP_JUDGE=1 keeps the stage). Comparator output ends:\n"
        ++ "\n".intercalate (lines.drop (lines.length - 25)))
    else die ("REJECTED:\n" ++ "\n".intercalate errs)
  finally
    if (← IO.getEnv "MIL_KEEP_JUDGE").isSome then IO.eprintln s!"staged judge kept at {stage}"
    else IO.FS.removeDirAll stage

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

/-- `mil judge`: generate the solution, build, and run the comparator in a staged judge workspace. -/
def judge (cfgPath : FilePath) (paranoid : Bool) : IO Unit := do
  let cfg ← loadConfig cfgPath
  let base ← IO.FS.realPath (cfgPath.parent.getD ".")
  run "lake" #["build"] base
  contract cfgPath
  solution cfgPath
  run "lake" #["build"] (base / cfg.implDir)
  -- build the solution in place too (not a default target in the pure template): the audit's
  -- verified-code check imports it, and the staged copy then replays it instead of rebuilding
  run "lake" #["build", cfg.solutionModule] (base / cfg.implDir)
  -- after the builds, so the manifests checked are the ones the builds used
  checkDeps cfg base
  let judgeCfg := Json.mkObj [
    ("challenge_module", cfg.specModule), ("solution_module", cfg.solutionModule),
    ("theorem_names", toJson (cfg.obligations.map (·.1))),
    ("definition_names", toJson (cfg.holes.map (·.1))),
    ("permitted_axioms", toJson ["propext", "Quot.sound", "Classical.choice"])]
  stagedComparator (base / cfg.implDir) judgeCfg paranoid

/-- `mil comparator <impl_dir> <config.json>`: the staged comparator for a package that has its
own comparator config instead of a `mil.json` (LeanKV). The package must already be built. -/
def comparatorCmd (implDir cfgFile : String) (paranoid : Bool) : IO Unit := do
  match Json.parse (← IO.FS.readFile cfgFile) with
  | .ok j => stagedComparator implDir j paranoid
  | .error e => die s!"{cfgFile}: {e}"

/-- Files covered by the lock. -/
def lockList (cfg : Config) : List String :=
  -- an app with an `audit` section also locks the spec's resolved dependencies (the spec's
  -- meaning depends on them); legacy locks, frozen before this, cover only the files
  ["lean-toolchain", "lakefile.lean", "mil.json"] ++
    (if cfg.audit.isSome then ["lake-manifest.json"] else []) ++ cfg.lockFiles

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
  unless rc == 0 do die "spec.lock MISMATCH: the frozen spec was changed"
  -- `sha256sum --check` verifies only the lines present. Deleting a file's line from spec.lock
  -- and then editing that file would pass it, so the lock must also cover exactly the files
  -- mil.json declares. mil.json itself is always in that set, and its hash was just checked, so
  -- its `lock_files` cannot have been shortened.
  let cfg ← loadConfig cfgPath
  let listed := (body.splitOn "\n").filterMap fun l =>
    match (l.trimAscii.toString.splitOn " ").filter (· != "") with
    | _ :: f :: _ => some ((if f.startsWith "*" then (f.drop 1).toString else f))
    | _ => none
  let want := lockList cfg
  let missing := want.filter (!listed.contains ·)
  let extra := listed.filter (!want.contains ·)
  unless missing.isEmpty && extra.isEmpty do
    die s!"spec.lock MISMATCH: the lock does not cover exactly mil.json's files (missing: {missing}; unexpected: {extra})"
  IO.println "spec.lock OK"

/-- `mil review`: SPEC_REVIEW.md generated from the elaborated spec (`#spec_review`). -/
def review (cfgPath : FilePath) : IO Unit := do
  let cfg ← loadConfig cfgPath
  let base := cfgPath.parent.getD "."
  let pfx := cfg.specModule
  IO.FS.writeFile (base / ".mil_review.lean") s!"import {pfx}\nimport MakeItLean.Review\n#spec_review {pfx} \"SPEC_REVIEW.md\"\n"
  -- An external app's build never imports MakeItLean.Review, so its git copy is not built yet.
  run "lake" #["build", pfx, "MakeItLean.Review"] base
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

/-- The framework checkout (`MIL_HOME`): the environment variable if set, else the checkout this
`mil` binary was built in (`<home>/cli/.lake/build/bin/mil`), else the nearest enclosing checkout. -/
def milHome : IO FilePath := do
  let ok (h : FilePath) : IO Bool := (h / "lean" / "MakeItLean" / "Gates.lean").pathExists
  if let some h ← IO.getEnv "MIL_HOME" then
    let h ← IO.FS.realPath h
    if ← ok h then return h
    die s!"MIL_HOME={h} is not a MakeItLean checkout (no lean/MakeItLean/Gates.lean)"
  let exe ← IO.FS.realPath (← IO.appPath)
  if let some h := exe.parent >>= (·.parent) >>= (·.parent) >>= (·.parent) >>= (·.parent) then
    if ← ok h then return h
  findRoot (← IO.currentDir)

/-- Where an app outside the checkout fetches the framework from: `MIL_GIT_URL` / `MIL_GIT_REV`,
else the checkout's `origin` URL and its `HEAD` commit (pinned, so the build is reproducible). -/
def gitSource (home : FilePath) : IO (String × String) := do
  let g (args : Array String) : IO String := do
    return (← capture "git" (#["-C", home.toString] ++ args)).trimAscii.toString
  let url ← match ← IO.getEnv "MIL_GIT_URL" with
    | some u => pure u
    | none => g #["remote", "get-url", "origin"]
  let rev ← match ← IO.getEnv "MIL_GIT_REV" with
    | some r => pure r
    | none => g #["rev-parse", "HEAD"]
  if (← g #["status", "--porcelain", "--untracked-files=no"]) != "" then
    IO.eprintln s!"warning: {home} has uncommitted changes; the app pins commit {rev}, which does not have them"
  if (← IO.getEnv "MIL_GIT_URL").isNone && (← g #["branch", "-r", "--contains", rev]) == "" then
    IO.eprintln s!"warning: commit {rev} is on no remote branch; push it, or `lake update` cannot fetch it"
  return (url, rev)

/-- Rewrite every `"MIL_ROOT/<sub>"` (a template's path `require`) into a pinned git require
`git "<url>" @ "<rev>" / "<sub>"`. -/
def gitRequires (s url rev : String) : String :=
  match s.splitOn "\"MIL_ROOT/" with
  | first :: rest@(_ :: _) => first ++ String.join (rest.map fun chunk =>
      match chunk.splitOn "\"" with
      | sub :: tl => s!"git \"{url}\" @ \"{rev}\" / \"{sub}\"" ++ "\"".intercalate tl
      | [] => chunk)
  | _ => s

/-- `mil init --agent claude|codex` (apps outside the checkout): the agent's instructions. The
framework docs are written for apps inside the checkout; a preamble maps their paths onto
`MIL_HOME` and this app, and the docs themselves are used unchanged. -/
def agentSetup (agent : String) (home app : FilePath) : IO Unit := do
  let h := home.toString
  let preamble := s!"# MakeItLean app outside the framework checkout

`mil init` created this app outside the MakeItLean checkout. The framework is at
`MIL_HOME = {h}`, and `mil` is `{h}/cli/.lake/build/bin/mil`. The framework's instructions are
written for apps inside the checkout; read them with this mapping:

- `agents/`, `knowledge/`, `templates/`, `tools/`, `lean/`, `cli/` and the worked examples
  (`examples/counter/`, `examples/ledger/`, `examples/kvstore/`) are under `MIL_HOME`. They are
  read-only to every role.
- `examples/<app>/` means this app: `{app}`.
- The app fetches the framework by a git require pinned to a commit (see `lakefile.lean`). That pin
  is part of the frozen spec once `spec.lock` exists; changing it needs a new sign-off.

"
  match agent with
  | "codex" =>
    let doc ← IO.FS.readFile (home / "agents" / "AGENTS.md")
    IO.FS.writeFile (app / "AGENTS.md") (preamble ++ "---\n\n" ++ doc)
    IO.println s!"wrote {app}/AGENTS.md (Codex reads it from the directory it starts in: start Codex in the app directory). No hooks: enforcement is `mil check-lock` and `mil audit`."
  | _ =>
    IO.FS.createDirAll (app / ".claude" / "agents")
    for e in ← (home / ".claude" / "agents").readDir do
      if e.fileName.startsWith "mil-" && e.path.extension == some "md" then
        let s ← IO.FS.readFile e.path
        let s := match s.splitOn "\n---\n" with
          | fm :: rest@(_ :: _) => fm ++ "\n---\n\n" ++ preamble ++ "\n---\n".intercalate rest
          | _ => preamble ++ s
        IO.FS.writeFile (app / ".claude" / "agents" / e.fileName) s
    let hook (script msg : String) : String :=
      "          {\n            \"type\": \"command\",\n            \"command\": \"python3 -I \\\"" ++ h ++
      "/tools/hooks/" ++ script ++ "\\\"\",\n            \"timeout\": 20,\n            \"statusMessage\": \"" ++ msg ++ "\"\n          }"
    IO.FS.writeFile (app / ".claude" / "settings.json")
      ("{\n  \"hooks\": {\n    \"PreToolUse\": [\n      {\n        \"matcher\": \"Edit|Write|MultiEdit|NotebookEdit|Bash\",\n        \"hooks\": [\n" ++
       hook "guard_locked.py" "Checking frozen spec files" ++ ",\n" ++
       hook "guard_role.py" "Checking agent role permissions" ++ "\n        ]\n      }\n    ]\n  }\n}\n")
    IO.FS.writeFile (app / "CLAUDE.md") (preamble ++
      s!"Follow `{h}/agents/AGENTS.md`. The role agents are in `.claude/agents/`; the guard hooks in `.claude/settings.json` enforce frozen files and role areas.\n")
    IO.println s!"wrote {app}/CLAUDE.md, .claude/settings.json (guard hooks) and .claude/agents/ (roles). Start Claude Code in the app directory so they apply."

/-- `mil init [--pure]`: copy templates/app (an app on the LeanKV substrate) or templates/pure (a
pure function) into `dir`, renaming `AppName`/`appname`. Inside the framework checkout the app
reaches the framework by relative paths (`MIL_ROOT` ↦ `../..`, as the examples do); anywhere else
by git requires pinned to a commit. -/
def init (name dir : String) (pure : Bool := false) (agent : Option String := none) : IO Unit := do
  let root ← milHome
  let tmpl := root / "templates" / (if pure then "pure" else "app")
  if ← (FilePath.mk dir).pathExists then die s!"{dir} already exists"
  IO.FS.createDirAll ((FilePath.mk dir).parent.getD ".")
  run "cp" #["-r", tmpl.toString, dir]
  let absDir ← IO.FS.realPath dir
  let inside := (comps root).isPrefixOf (comps absDir)
  let up := "/".intercalate (((comps absDir).drop (comps root).length).map fun _ => "..")
  let (url, rev) ← if inside then Pure.pure ("", "") else gitSource root
  let files := (← capture "find" #[dir, "-type", "f"]).splitOn "\n" |>.filter (· != "")
  let lower := name.decapitalize
  for f in files do
    let s := ((← IO.FS.readFile f).replace "AppName" name).replace "appname" lower
    -- MIL_TOOLS: the framework's tools/ directory, as seen from the app's impl/ directory
    let s := if inside then (s.replace "MIL_TOOLS" ("../" ++ up ++ "/tools")).replace "MIL_ROOT" up
      else gitRequires (s.replace "MIL_TOOLS" ("${MIL_HOME:-" ++ root.toString ++ "}/tools")) url rev
    IO.FS.writeFile f s
  for d in (← capture "find" #[dir, "-depth", "-name", "*AppName*"]).splitOn "\n" |>.filter (· != "") do
    run "mv" #[d, d.replace "AppName" name]
  let how := if inside then "framework by relative path" else s!"framework from {url} at {rev.take 12}"
  IO.println s!"created {dir} (spec package; implementation in {dir}/impl; {how}). Next: write REQUIREMENTS.md (Stage 0)."
  if let some a := agent then
    if inside then IO.println "--agent: inside the checkout the repository's own AGENTS.md and .claude/ apply; nothing written"
    else agentSetup a root absDir

/-- `mil init [--pure] [--agent claude|codex] <AppName> <dir>`, flags in any order. -/
partial def initArgs (args : List String) (pure : Bool := false) (agent : Option String := none) : IO Unit :=
  match args with
  | "--pure" :: r => initArgs r true agent
  | "--agent" :: a :: r =>
    if a == "claude" || a == "codex" then initArgs r pure (some a) else die s!"--agent: claude or codex, not {a}"
  | [n, d] => init n d pure agent
  | _ => die "usage: mil init [--pure] [--agent claude|codex] <AppName> <dir>"

/-- The verified-code audit `mil` generates from `mil.json`'s locked `audit` section. Nothing in it
comes from the implementation, so the implementation cannot narrow it. For a substrate app it also
pins the three end-to-end facts to the frozen spec: `pickOk` and `refines` (what LeanKV's
`app_crash_consistent` needs), and the statement of the `crash_consistent` theorem `TRUST.md` cites. -/
def generatedAudit (cfg : Config) (a : AuditCfg) : String :=
  let solRoot := (cfg.solutionModule.takeWhile (· != '.')).toString
  let shell := if a.shell.isEmpty then [s!"{solRoot}.NoShell"] else a.shell
  let imports := cfg.solutionImports ++ [cfg.solutionModule, "MakeItLean.Gates"] ++
    (if a.substrate.isSome then ["LeanKVImpl.Proofs"] else [])
  let header := "-- GENERATED by `mil audit` from mil.json's `audit` section. Do not edit.\n" ++
    String.join (imports.map (s!"import {·}\n"))
  let core := s!"\n#audit_verified {" ".intercalate (a.verified ++ [solRoot])} forbid_imports {" ".intercalate shell}\n"
  let pins := match a.substrate with
    | none => ""
    | some s =>
      let opens := s!"open LeanKV.Spec LeanKV.Proofs {cfg.specModule} in\n"
      let step := s!"(fun (s : {s.state}) (c : {s.cmd} ByteArray) => (cstep s (c.map toBytes)).1)"
      let pr := s!"(fun st (c : {s.cmd} ByteArray) => pickRef st (c.map toBytes))"
      s!"\n-- End-to-end facts, pinned to the frozen spec's `dec`, `cstep`, `pickRef` and `toBytes`.\n" ++
      opens ++ s!"example : Refines dec {step} {pr} := {s.refines}\n" ++
      opens ++ s!"example : PickOk {s.pick} {pr} := {s.pickOk}\n" ++
      opens ++ s!"example \{c0 : Bytes} \{s0 : Store} (hs0 : logState c0 = some s0)
    (cs : List ({s.cmd} ByteArray)) (φ : List Fault) (ch : CrashChoice) :
    let out := (do
        match ← (LeanKV.Core.openStore : FsM _) with
        | .error r => pure (Except.error r)
        | .ok h => Except.ok <$> LeanKV.Core.execPick {s.pick} h cs : FsM _).run (startState c0 φ)
    AppOutcome dec {step} {pr} s0 cs out.1 (crashOutcome out.2.disk ch) :=
  {s.crashConsistent} hs0 cs φ ch\n"
  header ++ core ++ pins

/-- A legacy app (no `audit` section, frozen before the audit was generated): its own
`impl/audit.lean` runs only if its sha256 is listed in the framework's `lean/legacy_audits.json`,
so the implementation cannot change it. -/
def legacyAudit (cfg : Config) (base : FilePath) : IO Unit := do
  let impl := base / cfg.implDir
  let f := impl / "audit.lean"
  unless ← f.pathExists do die s!"{f} is missing, and mil.json has no `audit` section to generate it from"
  let sha := ((← capture "sha256sum" #[f.toString]).takeWhile (· != ' ')).toString
  let listFile := (← milHome) / "lean" / "legacy_audits.json"
  let known ← match Json.parse (← IO.FS.readFile listFile) with
    | .ok j => match j.getObjValAs? (Array Json) "audits" with
      | .ok a => pure (a.toList.filterMap fun e => (e.getObjValAs? String "sha256").toOption)
      | .error e => die s!"{listFile}: audits: {e}"
    | .error e => die s!"{listFile}: {e}"
  unless known.contains sha do
    die s!"verified-code audit: {f} (sha256 {sha}) is not a known legacy audit, and mil.json has no `audit` section. Add the `audit` section (a spec change: new sign-off) so mil generates the audit."
  IO.println "WARNING: legacy audit (impl/audit.lean, pinned by hash in lean/legacy_audits.json); the spec's dependencies are not in the lock"
  run "lake" #["env", "lean", "audit.lean"] impl

/-- Stage 6's verified-code audit: generated from `mil.json` (or a hash-pinned legacy file). -/
def verifiedAudit (cfg : Config) (base : FilePath) : IO Unit := do
  match cfg.audit with
  | none => legacyAudit cfg base
  | some a =>
    if let some s := a.substrate then
      unless cfg.holes.any (·.2 == s.pick) do
        die s!"verified-code audit: audit.substrate.pick is {s.pick}, but no hole is filled with it (fill.json): the pinned facts would be about other code than the comparator checked"
    let impl := base / cfg.implDir
    let file := impl / ".mil_audit.lean"
    IO.FS.writeFile file (generatedAudit cfg a)
    try run "lake" #["env", "lean", ".mil_audit.lean"] impl
    finally IO.FS.removeFile file

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
  IO.println "== verified-code audit"; verifiedAudit cfg base
  IO.println "== trust manifest and shell wiring"; trust cfg base
  IO.println (if ← (base / "spec.lock").pathExists then "AUDIT PASSED" else "AUDIT PASSED (UNFROZEN SPEC)")

def usage : String := "usage: mil init [--pure] [--agent claude|codex] <AppName> <dir> | solution|judge|contract|check-lock|review|audit <mil.json> | freeze <mil.json> <who> | judge --paranoid <mil.json> | audit --allow-unfrozen <mil.json> | comparator [--paranoid] <impl_dir> <config.json>"

def main (args : List String) : IO UInt32 := do
  try
    match args with
    | "init" :: r => initArgs r
    | ["solution", c] => solution c
    | ["judge", c] => judge c false
    | ["judge", "--paranoid", c] => judge c true
    | ["freeze", c, who] => freeze c who
    | ["check-lock", c] => checkLock c
    | ["review", c] => review c
    | ["audit", c] => audit c false
    | ["audit", "--allow-unfrozen", c] => audit c true
    | ["contract", c] => contract c
    | ["comparator", i, c] => comparatorCmd i c false
    | ["comparator", "--paranoid", i, c] => comparatorCmd i c true
    | _ => IO.eprintln usage; return 2
    return 0
  catch e => IO.eprintln s!"mil: {e}"; return 1

end Mil

def main (args : List String) : IO UInt32 := Mil.main args
