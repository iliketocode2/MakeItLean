/-! Bait spec: planted violations the spec gates must reject. -/
namespace BaitSpec
def undocumented : Nat := 1
/-- English: IMPLEMENTATION HOLE. A hole. -/
def hole : Nat := sorry
/-- English: A definition that calls the hole (forbidden). -/
def usesHole : Nat := hole + 1
/-- English: An obligation naming the hole (may be open). -/
theorem obligation : hole = hole := sorry
/-- English: A spec theorem left open (forbidden). -/
theorem notAnObligation : 1 + 1 = 2 := sorry
/-- English: A spec claim that names the hole only to escape proof (the contract gate's bait). -/
theorem smuggled (_ : hole = hole) : 2 + 2 = 4 := sorry
/-- English: A spec definition left unwritten (forbidden). -/
def unwritten : Nat := sorry
end BaitSpec
