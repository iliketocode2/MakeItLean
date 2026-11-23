# AppName — Trust manifest (Stage 6)

> TEMPLATE: rewrite every row for your function. `mil audit` checks that every theorem name cited
> here exists.

| Req | Requirement | Status | Evidence |
|---|---|---|---|
| R1 | Allowed inputs | Proven (by definition) | `maxOf_precond` |
| R2 | The result meets the postcondition on every allowed input | Proven, comparator ACCEPTED | `AppNameImpl.maxOf_ok` (fills `impl_maxOf_ok`) |
| Spec | The postcondition accepts each worked example and rejects the listed wrong answers | Checked at build time | `#guard` lines in `AppName/Spec/Properties.lean`; `maxOf_postcond_equal` |

## Trusted, not verified
1. **The spec itself:** that the precondition and postcondition say what the requirements mean
   (the user's sign-off; the worked examples check it on the listed inputs only).
2. **The Lean compiler and runtime.**
