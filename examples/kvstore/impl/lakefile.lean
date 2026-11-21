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
