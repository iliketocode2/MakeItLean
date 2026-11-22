import Lake
open Lake DSL

/-! `mil`: the MakeItLean command-line tool (plain Lean, no external dependencies). -/
package mil

@[default_target]
lean_exe mil where
  root := `Mil.Main
