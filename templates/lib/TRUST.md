# AppName — Trust manifest (Stage 6)

> TEMPLATE: rewrite every row for your library. `mil audit` checks that every theorem name cited
> here exists, and that every Proven row cites a name the audit anchors (a frozen spec declaration,
> an obligation or the proof filling it).

| Req | Requirement | Status | Evidence |
|---|---|---|---|
| R1 | Sets are strictly ascending; inserting keeps them so | Proven | `Ascending`, `ascending_insertSorted` |
| R2 | `insertSorted` adds in order; an element already present changes nothing | Proven, comparator ACCEPTED | `insertSorted`, `mem_insertSorted`; `impl_insertSorted_ok` (filled by `AppNameImpl.insertSorted_ok`) |
| R3 | `member` is true exactly for elements of the set | Proven, comparator ACCEPTED | `member`, `member_insertSorted`; `impl_member_ok` (filled by `AppNameImpl.member_ok`, which uses R1 to stop early) |
| R4 | `size` counts the elements; inserting adds at most one | Proven, comparator ACCEPTED | `size`, `size_insertSorted_le`; `impl_size_ok` (filled by `AppNameImpl.size_ok`) |
| Examples | The worked examples of REQUIREMENTS.md | Checked at build time | `#guard` lines in `AppName/Spec/Properties.lean` |

## Trusted, not verified
1. **The spec itself:** that the reference functions say what the requirements mean (the user's
   sign-off; the worked examples check it on the listed inputs only).
2. **The Lean compiler and runtime.**
3. **Callers keep the precondition:** `member`'s speed relies on its input being ascending. Sets
   built only with `insertSorted` from `[]` are (R1, proven); a caller that builds a list another
   way must check `Ascending` itself.
