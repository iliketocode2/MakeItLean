# LeanKV pilot: friction log

Phase 1 asks us to log every point of friction while following the workflow by hand. Each entry feeds Phase 2, when the framework is extracted from this pilot.

| Date | Stage | Friction | Resolution / framework implication |
|---|---|---|---|
| 2026-11-21 | 0 | The background PDFs could not be read: `poppler-utils` is missing and there is no `sudo`. | Extracted the text with `pypdf` in a scratch venv. **Framework:** the environment setup step should install `poppler-utils`. |
| 2026-11-21 | 0 | An outside reviewer (Gemini) was given only the chat summary, not the requirements doc. Most of its "please clarify" items were already in the doc. | **Framework:** reviewers, human or agent, must be given the document itself. `mil spec-review` should hand over the file, not a summary. |
| 2026-11-21 | 1 | Lean 4.36 removed `String.trimLeft`, which broke the doc-gate tool. | Used list operations instead. This confirms the toolchain-churn risk in PLAN.md. **Framework:** keep the gate tools to stable APIs and pin the toolchain. |
| 2026-11-21 | 1 | The first version of the English-doc gate flagged compiler-generated names: `.rec` and the helpers that `deriving` creates under instances. | Filter out recursors and any name nested under an instance. A negative test (one doc removed) confirmed the gate still fails when it should. **Framework:** ship `#assert_english_docs` in `lean/MakeItLean/` with that negative test. |
| 2026-11-21 | 1 | A requirement can only be enforced on an implementation the spec can see. R17 ("height ≤ c·log n") cannot be stated against an implementation whose type is left open, because its "height" could be defined as 0. | The user chose to have the spec fix a binary search tree (`Spec/Contract.lean`). Its in-order contents must equal the reference store, and its height must be ≤ 3·⌊log₂(n+1)⌋+2. A residual gap remains: shape is constrained, but how the operations use the tree is not. **Framework:** the spec-author role must ask, for each non-functional requirement, "what in the spec can see this?" |
