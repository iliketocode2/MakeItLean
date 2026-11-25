# Design lessons (spec and app shape)

From the LeanKV pilot, the Ledger exit tests and Phase 4. Each lesson changed how a later app was
built. Lean-level traps are in [LEAN_IDIOMS.md](LEAN_IDIOMS.md); reusable proven lemmas are in
[LEMMAS.md](LEMMAS.md).

## Specs
- **A requirement can only be enforced on what the spec can see.** "Height ≤ c·log n" cannot be
  stated about an implementation whose type is left open, because its height could be defined as
  0. Fix the representation in the spec where a requirement needs it (LeanKV fixes a search tree).
- **Holes appear only in theorem statements, never in definitions.** A spec definition that calls
  a hole breaks the comparator (definition heights differ between challenge and solution).
  `#assert_holes_only_in_theorems` enforces this.
- **Make the spec generic over the byte representation.** A spec on `List UInt8` forces the
  implementation to store a 1 MiB value as a million heap cells. Generic types let the
  implementation use `ByteArray` while the spec reasons with lists.
- **Ask whether the obvious format meets the requirements.** A plain log format (magic, length,
  CRC) broke the torn-write requirement, since a stored value can contain a complete record. Byte
  stuffing fixed it. Found while *stating* the theorem, before any code.
- **Prove canonical decoding** for any binary format: whatever decodes is exactly the encoding of
  what it decodes to. Every later format proof then works on the encoding.
- **If a requirement sums or lists the state, model the state as a sorted list**, mirroring the
  substrate's `Store`, not as a function. A function cannot express "the total" (Ledger R5, R13).
- **Decide with a lookup parameter.** When the spec's decision function takes a balance *lookup*
  as an argument, the implementation reuses it with a fast lookup, and the obligation proof is
  small (Ledger: about 20 lines; judge ACCEPTED on the first run).

## Validation before freeze
- **Give the spec's theorems teeth first.** A throwaway reference implementation plus three planted
  bugs, evaluated over 728 fault and crash scenarios: the reference passed everything, and each bug
  failed 42–126 scenarios. It costs minutes, and shows the theorems can fail.
- **Check that a critic's generator reaches the bug.** With 6 keys, an unbalanced "chain" tree
  stayed within the height bound and passed. With 26 keys it is caught in 298 of 300 runs.
- **Test the theorem's statement by evaluation before proving it.** False statements show up in
  seconds.

## Implementation and proof
- **Mirror the reference.** Write the fast code function by function in the shape of the spec
  function it replaces; the equality proof is then a correspondence (LeanKV's decoder, about 400
  lines, layer by layer).
- **Proof-licensed optimisation is cheap once the reference exists**: fast CRC (by `rfl` plus a loop
  induction), direct `ByteArray` encoder (about 40 lines), iterative splitter (about 50 lines), each
  2–5× faster, with the comparator still accepting.
- **Benchmark at the limits.** The only bug the proofs could not catch (stack overflow at 60 MB)
  was found by a benchmark at the R8a limits.

## Shells and tests
- **A non-Lean shell is transport only, checked by differential tests** against the Lean model
  (the oracle). Replay every literal example from the requirements, too: a mapping bug mirrored in
  the server and the adapter passes the differential test but not the replay.
- **Values the line protocol cannot carry** (empty names, spaces) need an agreed stand-in word that
  the model rejects as the spec says (Ledger's `?`).
- **Probe readiness without side effects**: an empty line is answered `ERR USAGE` without touching
  the store.

## Process
- **Reviewers, human or agent, get the document itself**, never a summary.
- **Every gate has a negative test**: plant the violation, expect the failure. Two audit gaps were
  found only this way (a `partial def` compiles to `opaque`; a spec `sorry` definition passed the
  axiom gate).
- **Push before running agents in a worktree.** A worktree sees only commits.
