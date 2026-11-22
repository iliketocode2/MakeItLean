import MakeItLean.Gates
import MakeItLeanTest.Bait.Spec
import MakeItLeanTest.Bait.Good
import MakeItLeanTest.Bait.Verified

/-! Negative and positive tests for every gate. The build fails if any gate stops rejecting its
planted violations, or starts rejecting the well-formed spec. -/

/-- error: English-doc gate: 1 declaration(s) lack an `English:` doc: [BaitSpec.undocumented] -/
#guard_msgs in #assert_english_docs MakeItLeanTest.Bait.Spec

/-- error: Hole gate: definitions use implementation holes: [(BaitSpec.usesHole, [BaitSpec.hole])] -/
#guard_msgs in #assert_holes_only_in_theorems MakeItLeanTest.Bait.Spec

/-- error: Spec-axiom gate: [BaitSpec.notAnObligation uses sorryAx] -/
#guard_msgs in #assert_spec_axioms MakeItLeanTest.Bait.Spec

/-- info: English-doc gate: OK for modules under MakeItLeanTest.Bait.Good -/
#guard_msgs in #assert_english_docs MakeItLeanTest.Bait.Good

/-- info: Hole gate: OK (1 holes, used only in theorem statements) -/
#guard_msgs in #assert_holes_only_in_theorems MakeItLeanTest.Bait.Good

/-- info: Spec-axiom gate: OK (2 theorems; 1 obligations open) -/
#guard_msgs in #assert_spec_axioms MakeItLeanTest.Bait.Good

/--
error: Verified-code audit FAILED:
MakeItLeanTest.Bait.Verified imports MakeItLeanTest.Bait.Shell
axiom BaitVerified.trustMe used by BaitVerified.viaAxiom
axiom sorryAx used by BaitVerified.cheat
implemented_by: BaitVerified.impl
opaque/partial: BaitVerified.loop
unsafe: BaitVerified.uns
-/
#guard_msgs in #audit_verified MakeItLeanTest.Bait.Verified forbid_imports MakeItLeanTest.Bait.Shell
