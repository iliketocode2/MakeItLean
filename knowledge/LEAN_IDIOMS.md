# Lean 4.36 proof idioms and traps (learned in the LeanKV pilot)

Each item cost real time in the pilot. Check here before fighting a tactic.

## Forbidden or unusable
- **`bv_decide` and `native_decide` are unusable**: their proofs rely on `Lean.ofReduceBool`, which the comparator's axiom whitelist (`propext`, `Quot.sound`, `Classical.choice`) rejects. Prove bit-level facts by hand, or keep code in a form provable by `rfl` and `simp`.
- **`partial def`** compiles to an `opaque` constant: proofs cannot see its body, and the verified-code audit rejects it. Use structural recursion, or `termination_by` with an explicit measure (often `b.size - i` for array loops).
- **Mathlib is not available.** `List.Forall₂`, `le_trans`, `Nat.strong_induction_on` and `List.drop_append_of_le_length'` do not exist. Use `Nat.strongRecOn`, `UInt8.le_trans`/`Nat.le_trans`, and write small helpers yourself.

## Renamed or removed APIs (4.36)
- `String.trimLeft`, `String.trim`, `String.dropRight`, `String.mk` are gone or deprecated: work on `s.toList` / `s.toUTF8`, use `String.ofList`.
- `if_pos`, `if_neg`, `dif_pos`, `dif_neg`, `if_true` are deprecated (they still work, with warnings). Prefer `simp only [h, ↓reduceIte]` / `↓reduceDIte`.
- `ByteArray.toList` is an irreducible loop with no lemmas: rewrite with `toBytes_eq : toBytes b = b.data.toList` (LeanKV `Proofs/Bytes.lean`) first.

## Tactic traps
- **Unfolding a constant inside `decide` breaks its instance.** For `validKey k = true` where `validKey` uses `maxKeyLen` inside a `decide`: first `simp only [validKey, Bool.and_eq_true, decide_eq_true_eq]`, *then* `simp only [maxKeyLen]`, then `omega`.
- **`simp` cannot generate equation lemmas** for some definitions with overlapping wildcard patterns ("failed to generate equational theorem"). Use `delta f` or `unfold f`, then `simp`.
- **Literal patterns in `match`** (`| 0xC7 :: rest => …`): the equation for a *variable* head needs side conditions. `rw [f]` then `all_goals (intros; simp_all)` to discharge them.
- **`cases h : e` replaces `e` in the goal**, not in hypotheses. A later `rw [h]` on the goal then finds nothing: the goal already has the constructor.
- **do-notation in `Option`/state monads** does not simplify by itself. After `rw [h1] at h`, use `simp only at h` to beta- and iota-reduce, then continue with the next bind. For `StateT` on `Id`, prove one `run` lemma per primitive operation (by `cases` + `rfl`) and rewrite with those.
- **`if false = true then …`** stays unreduced: add `Bool.false_eq_true` to `simp only`.
- **Unused `simp` arguments** are linted. Harmless, but clean them up.
- **Dot notation needs the full namespace.** For `hs : LState.Good s`, `hs.set` resolves only to a
  lemma named `LState.Good.set`; a lemma named `Good.set` is not found (Ledger).
- **`←` inside a pure expression is rejected** ("nested action must be nested inside a `do`
  expression"), e.g. `pure (if ← p.pathExists then a else b)`. Write `if ← p.pathExists then pure a else pure b`.

## Lake and the runtime (4.36)
- **Spec and implementation packages need distinct module roots** (`LeanKV` / `LeanKVImpl`).
  Otherwise Lean looks for the implementation's modules in the spec package's build directory.
- **An executable named like a `require`d package collides** in the lakefile: set `exeName`.
- **Functions linked from C (`@[extern]`) do not run in the interpreter** (`#eval`). Test them through
  the built executable (the apps' `impl/test.sh`).
- **No `fsync` or `seek` in the standard library** (and `truncate` cuts only at the current
  position). A durable store needs a small trusted C leaf (LeanKV `impl/c/lkv_io.c`).
- **Recursion over bytes overflows the stack on large inputs** (LeanKV: a 60 MB batch). The proofs
  cannot see this; a benchmark at the input limits does. Use tail recursion or array loops with
  `termination_by`, proven equal to the list reference.
- **Two workspaces, two clones.** A spec package and its `impl/` package are separate Lake
  workspaces. With git dependencies each clones its own copy, and the build products disagree
  ("unknown module prefix" for a module that built fine). The templates set
  `packagesDir := "../.lake/packages"` in `impl/` so there is one clone (Phase 5).
- **A git `require` from a shallow clone hangs.** Lake fetches with `--filter=tree:0`, which
  deadlocks against a shallow source repository (CI's default `actions/checkout`). Require from a
  full-history repository (`fetch-depth: 0` in CI).
- **Benchmarks: the compiler hoists pure computations out of a timing loop** ("0 µs"). Vary the
  input on every repetition, and build request text before the timer starts.

## Patterns that worked
- **Mirror the reference.** Write fast code function by function in the shape of the spec function it replaces. The equality proof is then a step-by-step correspondence (the pilot's `ByteArray` decoder matched the list spec layer by layer).
- **Accumulator loops**: prove `loop i acc = acc ⊕ spec (drop i input)` by `induction h : size - i generalizing i acc`.
- **Canonical decoding.** Prove "whatever decodes is exactly the encoding of what it decodes to". Then a log that decodes cleanly *is* `encodeLog records`, and every format lemma applies.
- **`omega`** handles all the height, length and offset arithmetic, including `/` and `%` by literals. Give it the facts as hypotheses.
- **Test before proving.** Evaluate the theorem's statement on random inputs (`#eval`/`#guard`) first; it catches false statements in seconds.
- **Gate every claim with a negative test**: plant the violation, expect the failure.
