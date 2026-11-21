import Lake
open Lake DSL

/-! LeanKV implementation (Stage 3+). Depends on the frozen spec package in `..`, never edits it. -/
package leankvImpl

require leankv from ".."

/-- The implementation core: index, log codec, recovery and the store, generic over `LogFile m`. -/
@[default_target]
lean_lib LeanKVCore where
  roots := #[`LeanKVImpl.Core]
