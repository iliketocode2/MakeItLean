# AppName — Requirements (Stage 0, DRAFT for approval)

> A **pure-function app** (`mil init --pure`): one function, specified by a precondition and a
> postcondition. Plain English; every requirement gets an ID. Mark open questions **[DECIDE]**.

## 1. What the function does
<one paragraph>

## 2. Signature
`maxOf (a : Int) (b : Int) : Int`

## 3. Requirements
- **R1. Allowed inputs (precondition).** …
- **R2. Correct result (postcondition).** …

## 4. Worked examples (each becomes `#guard` lines in `Spec/Properties.lean`)
| Input | Expected | Wrong answers the spec must reject |
|---|---|---|
| a = 3, b = 5 | 5 | 3 |

## 5. Non-goals
