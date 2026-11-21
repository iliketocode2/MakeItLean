import Lake
open Lake DSL

/-! LeanKV implementation (Stage 3+). Depends on the frozen spec package in `..`, never edits it. -/
package leankvImpl

require leankv from "spec"

/-- The implementation core: index, log codec, recovery and the store, generic over `LogFile m`. -/
@[default_target]
lean_lib LeanKVCore where
  roots := #[`LeanKVImpl.Core]

/-- Stage 4 proofs that the core meets the frozen spec's obligations. -/
@[default_target]
lean_lib LeanKVProofs where
  roots := #[`LeanKVImpl.Proofs]

/-- Generated solution: base copies of the frozen spec (minus holes) and the filled holes. -/
@[default_target]
lean_lib LeanKVSol where
  globs := #[.submodules `LeanKVSol]

/-! ## Stage 5: the trusted C leaf and the `leankv` executable -/

target lkv_io.o pkg : System.FilePath := do
  let oFile := pkg.buildDir / "c" / "lkv_io.o"
  let srcJob ← inputTextFile <| pkg.dir / "c" / "lkv_io.c"
  let weakArgs := #["-I", (← getLeanIncludeDir).toString]
  buildO oFile srcJob weakArgs #["-fPIC", "-O2"] "cc" getLeanTrace

extern_lib liblkvio pkg := do
  let ffiO ← lkv_io.o.fetch
  let name := nameToStaticLib "lkvio"
  buildStaticLib (pkg.staticLibDir / name) #[ffiO]

/-- The `leankv` CLI and server. -/
lean_exe leankvCli where
  exeName := "leankv"
  root := `LeanKVImpl.Shell.Main

/-- The trusted real-file shell (Stage 5). Not part of the verified core. -/
lean_lib LeanKVShell where
  roots := #[`LeanKVImpl.Shell.FileIO]

/-- Real-file differential self-test: the store on real files against the reference model. -/
lean_exe leankvSelftest where
  exeName := "leankv-selftest"
  root := `LeanKVImpl.Shell.SelfTest
