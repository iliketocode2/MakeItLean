import Lake
open Lake DSL

package leankv

/-- Gate tooling (English-doc checker). Candidate for extraction into the framework library in Phase 2. -/
lean_lib LeanKVTools where
  roots := #[`LeanKV.Tools.EnglishDocs]

/-- The frozen-spec-to-be: types, reference semantics, theorem statements. -/
lean_lib LeanKVSpec where
  roots := #[`LeanKV.Spec]
