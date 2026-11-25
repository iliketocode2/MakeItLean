# AppName — Requirements (Stage 0, DRAFT for approval)

> A **library** (`mil init --lib`): several related functions over shared types, each specified by
> a simple **reference implementation**, plus properties that relate them. The implementation may
> be faster than the reference, as long as it is proven equal to it. Plain English; every
> requirement gets an ID. Mark open questions **[DECIDE]**.

## 1. What the library does
<one paragraph>

## 2. Types and functions
- `NatSet`: a set of natural numbers, as a strictly ascending list.
- `insertSorted (x : Nat) (s : NatSet) : NatSet`, `member (x : Nat) (s : NatSet) : Bool`,
  `size (s : NatSet) : Nat`.

## 3. Requirements
- **R1. Valid sets.** A set is strictly ascending (no repeats). Inserting into a valid set gives a
  valid set.
- **R2. insertSorted.** Adds the element in order; adding an element already present changes nothing.
- **R3. member.** True exactly when the element is in the set.
- **R4. size.** The number of elements; inserting adds at most one.
- **R5. Speed (allowed, not required).** `member` may stop at the first element larger than the one
  looked for, relying on R1.

## 4. Worked examples (each becomes `#guard` lines in `Spec/Properties.lean`)
| Call | Expected |
|---|---|
| insert 3, then 1, then 2 into the empty set | [1, 2, 3] |
| insertSorted 2 [1, 2, 3] | [1, 2, 3] |
| member 2 [1, 2, 3]; member 4 [1, 2, 3] | true; false |
| size [1, 2, 3] | 3 |

## 5. Non-goals
