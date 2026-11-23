import MakeItLean.Gates
import MakeItLeanTest.Bait.Spec
import MakeItLeanTest.Bait.Good
import MakeItLeanTest.Bait.Verified
import MakeItLeanTest.Bait.ShellWiring

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
axiom sorryAx used by BaitVerified.hiddenSorry
implemented_by: BaitVerified.impl
opaque/partial: BaitVerified.loop
unsafe: BaitVerified.uns
-/
#guard_msgs in #audit_verified MakeItLeanTest.Bait.Verified forbid_imports MakeItLeanTest.Bait.Shell

/-! The contract gate. The spec-axiom gate above accepts `BaitSpec.smuggled` (it names the hole, so
it counts as an obligation); the contract gate catches it because `mil.json` does not list it. -/

/--
error: Contract gate FAILED:
theorem BaitSpec.smuggled names a hole but is not a listed obligation (the comparator would never check it)
-/
#guard_msgs in #assert_contract MakeItLeanTest.Bait.Spec (BaitSpec.hole) (BaitSpec.obligation)

/--
error: Contract gate FAILED:
mil.json lists BaitSpec.ghost, which is not an implementation hole
mil.json lists BaitSpec.twice_id, which is not a theorem naming a hole
-/
#guard_msgs in #assert_contract MakeItLeanTest.Bait.Spec (BaitSpec.hole BaitSpec.ghost) (BaitSpec.obligation BaitSpec.smuggled BaitSpec.twice_id)

/-- info: Contract gate: OK (1 holes, 1 obligations, matching mil.json) -/
#guard_msgs in #assert_contract MakeItLeanTest.Bait.Good (GoodSpec.step) (GoodSpec.step_ok)

/-! The trust gate: a manifest citing a theorem that does not exist is rejected; error codes,
commands and file names are not mistaken for theorem names. -/

/-- error: Trust gate: MakeItLeanTest/Bait/TRUST_bait.md cites names that do not exist: [made_up_theorem] -/
#guard_msgs in #assert_trust_cites "MakeItLeanTest/Bait/TRUST_bait.md" "MakeItLeanTest/Bait"

/-- error: Trust gate: MakeItLeanTest/Bait/NO_TRUST.md does not exist (Stage 6 requires a trust manifest) -/
#guard_msgs in #assert_trust_cites "MakeItLeanTest/Bait/NO_TRUST.md" "MakeItLeanTest/Bait"

/-! The shell gate: the shell's entry point must reach the verified functions. -/
/-- info: Shell gate: OK (BaitWiring.honestMain reaches [BaitWiring.verifiedStep]) -/
#guard_msgs in #assert_shell_calls BaitWiring.honestMain within MakeItLeanTest (BaitWiring.verifiedStep)

/-- error: Shell gate: BaitWiring.bypassMain never reaches [BaitWiring.verifiedStep] (the shell bypasses the verified code) -/
#guard_msgs in #assert_shell_calls BaitWiring.bypassMain within MakeItLeanTest (BaitWiring.verifiedStep)
