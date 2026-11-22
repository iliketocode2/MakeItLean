import Lake
open Lake DSL

/-! MakeItLean: the framework library (gates, bytes, durable store). Apps `require` it. -/
package makeitlean

@[default_target]
lean_lib MakeItLean where
  roots := #[`MakeItLean]

/-- Negative tests for the gates: planted violations each gate must reject. -/
@[default_target]
lean_lib MakeItLeanTest where
  globs := #[.submodules `MakeItLeanTest]
