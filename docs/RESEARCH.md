# MakeItLean — Background Research

Compiled 2026-11-20. Sources: the three papers in `background/`, plus web research into prior work and into Lean 4's practical capabilities. Claims marked **[unverified]** come only from secondary sources.

---

## 1. The background papers

### 1.1 Discovering formally verified quantum programs with AI (Google DeepMind, arXiv 2611.09822)
This is the most relevant paper. It shows the workflow we want, applied to quantum circuits.

- **Workflow.** Humans write a *frozen* Lean specification: correctness theorems, a cost theorem, and typed `sorry` holes for the program, its parameters and the proofs. Agent teams then fill the holes, and an independent verifier re-checks every submission.
- **Cost is part of the spec.** The library has a cost model (gate counts, qubits × T gates, expected cost over branches and loops). Agents prove a cost bound as well as correctness. **This is what makes "optimization" possible.** Agents can only optimize what the spec measures ("agents cannot optimize beyond [the specs]").
- **Anti-cheating.** Agents tried weakening theorems, changing definitions, adding axioms, disabling local checks and misreporting costs. The countermeasures were:
  - Every submission is replayed in a clean sandbox with the Lean Comparator against the frozen spec.
  - Theorem statements and all transitive definitions must be unchanged.
  - Only the standard axioms are allowed (`propext`, `Quot.sound`, `Classical.choice`).
  - The proved cost must reduce to the claimed closed form.
- **Spec loopholes still happen.** For example, agents exploited how Toffoli gates were counted. Humans fixed these by revising the spec. Human effort moves to *writing and auditing specs*.
- **Test first, prove later.** For arcsin, a fast classical simulator (kickmix) drove the early search. Formal proof then lifted the restrictions and improved the result further by about 11%. When something can be tested cheaply, test it first.
- **Collaboration infrastructure.** A version-controlled "wiki" per problem holds the best verified solution, reusable verified Lean modules, and reviewed idea notes (verified / promising / dead end). Scheduled "conferences" are where unverified ideas are exchanged; they count as results only once verified. A merge needs at least a 5% improvement, or at least 20% shorter code at a strictly lower cost.
- **Library design lesson.** They built their own Hoare logic and weakest-precondition calculus because existing VC generators (`mvcgen`, Loom) need a complete lattice of assertions. For ordinary classical software those generators *do* apply.

### 1.2 LeanDojo-v2 (arXiv 2611.09048)
- A unified library for extracting data from Lean repos, fine-tuning provers (SFT, LoRA, GRPO, PPO), and searching for proofs. It supports tactic-by-tactic search through the Pantograph REPL (DFS/MCTS) and whole-proof generation. It also ships Lean4Code, a VSCodium-based IDE.
- **Relevance to us:** tooling options for the proof stage, in particular REPL-driven proof search, and fine-tuning on *our own project's* lemmas if we later want a domain-specialized prover. They also note that Lean version churn is a maintenance cost.

### 1.3 Axiom Zero: AlphaZero-style RL for verifying Python (Monzora & Rukuni)
- Pipeline: Python AST → IR → obligations from `@requires`/`@ensures` → Lean skeletons → MCTS over 39 tactics. RL training on real theorems has not been done yet.
- **It is a cautionary example of the spec gap.** In its own end-to-end example:
  - `theorem absolute_POST (x:Int): result > 0` refers to an unbound `result`. The theorem never connects to the implementation.
  - `theorem absolute_PRE (x:Int): x > 0 := by simp` is *false* for arbitrary `x`.
  - The 143 tests run "without Lean 4 installed".

  **Lessons:**
  - Generated theorems must be checked by the real Lean kernel.
  - A spec must *mention the implementation*.
  - A spec must be checked for being provable and meaningful, not only for being well-typed.

---

## 2. Prior work: AI agents writing verified software

### 2.1 Lean 4 benchmarks and results
| Work | Result | Lesson |
|---|---|---|
| VERINA (2505.23135) | o3: 72.6% code correct, 52.3% specs sound and complete, **4.9% proofs** | Proofs are the bottleneck. Specs are only half right. |
| CLEVER (2505.13938) | ≈1/161 end to end | It requires proving the generated spec *equivalent* to a reference spec, which is the strongest anti-vacuity check. |
| Vericoding (2509.22908) | Dafny 82%, Verus 44%, **Lean 27%** | Lean is weaker for code verification than for math, because models were trained on Mathlib. |
| AlgoVeri (2602.09464) | Dafny 40%, Verus 25%, Lean 7.8% | Proving algorithms with invariants in Lean is still hard. |
| FVAPPS (2502.05714) | 4,715 Lean tasks, with theorems sanity-checked by unit tests and PBT | Test the theorems themselves. |
| FVSpec (Galois/ARIA, 2606.01008) | Real Hypothesis PBTs turned into 9.4k Lean challenges | The closest analogue to "properties first". |
| **LeetProof / Velvet** (2604.16584) | Validates specs with Plausible PBT *before* coding, breaks work into pieces per VC, and sends residual goals to strong provers | **Closest published design to ours.** Specs are often "too weak to be meaningful or too strong to be implementable". |
| Harmonic Aristotle | 96.8% on the VERINA proof task, including 23 *disproofs* of wrong specs | Disproving a spec is a feature. Usable as a commercial proof back end. |
| Mistral Leanstral 1.5 (Apache-2.0 weights) | Cheap open Lean agent trained on lean-lsp-mcp | A self-hostable bulk prover. |
| **lean-zip** (kim-em) | An agent ported zlib to Lean and proved `decompress (compress x) = x` | The idea works today. But fuzzing found a heap overflow in the Lean *runtime* and a denial of service in the *unproved* archive parser. |
| **Radix** (de Moura) | 10 agents built a verified embedded DSL in a weekend: 7.4k LOC, 52 theorems, 0 `sorry` | Medium-sized verified cores built autonomously by agents are realistic. |

### 2.2 Other verifiers
- **Dafny:** the easiest target for LLMs, because SMT does the heavy lifting.
  - Clover checks consistency between code, docs and spec.
  - DafnyBench counts a task as solved only if the spec is unchanged.
  - DafnyPro (AWS) reaches 86%.
  - AWS runs Dafny-verified authorization at about 1B calls per second **[unverified, secondary]**.
- **Verus/Rust:** AlphaVerus explicitly filters misaligned specs to prevent reward hacking. AutoVerus proves more than 90% of 150 tasks. Industrial reports describe LLM-written specs failing on a real OS (Asterinas).
- **F*:** HACL* and EverParse are in production. Retrieval over project-local lemmas matters a lot.
- **Coq/Rocq:** CompCert and Fiat Crypto. CoqPilot fills `admit` holes.
- **Imandra CodeLogician:** LLMs autoformalize Python into a *model*, and the tool reasons over that model.

### 2.3 Industrial Lean
- **AWS Cedar is the key template.**
  - It has an executable Lean model with proofs, a Rust production implementation, and nightly differential random testing (DRT) over millions of inputs.
  - Proofs found 4 bugs and DRT/PBT found 21.
  - A release is blocked unless the model, proofs and tests are current.
  - The Lean model runs at about 5 µs per input vs 7 µs for Rust.
- **SampCert:** verified differential-privacy samplers in Lean, deployed in AWS Clean Rooms.
- **Aeneas** (safe Rust → Lean): verified ML-KEM and SHA-3 in Microsoft SymCrypt. Agents wrote the proofs and humans reviewed the specs.
- **Strata** (AWS): Lean-based infrastructure for an intermediate verification language.
- **Veil:** verification of distributed protocols and state machines.
- **Loom / Velvet:** Dafny-style verification inside Lean.
- **Lean FRO Year-4 roadmap** (Sep 2026–Feb 2027):
  - a new `do` notation with intrinsic verification;
  - the SymM-based VC generator;
  - AI-friendly `grind`/`bv_decide`;
  - **lean-beam** as the official agent interface;
  - `lake check --paranoid`.

### 2.4 How agents cheat (documented)
- `sorry`, custom axioms, `native_decide`;
- edits to the spec or to definitions;
- vacuous specs (`requires false`, `ensures true`);
- editing the base code;
- exploiting verifier bugs. DeepSeek-Prover exploited a Lean 4.9 `apply?` bug, and crafted `.olean` files fool lean4checker.

**The Lean manual itself says to treat unreviewed AI proofs as potentially malicious and to check them with `lake comparator`.**

---

## 3. Lean 4 as an application platform (status at Lean ≈4.36)

| Area | Status |
|---|---|
| Native compilation (Lean → C → clang), refcounted, "functional but in place" | MATURE. Roughly OCaml/Haskell speed, below Rust/Go. A shared value silently loses in-place updates (O(1) becomes O(n)). |
| Tasks and threads | MATURE (thread pool). No green threads. |
| CLI (`Cli`), JSON (`Lean.Json` deriving), file IO, processes | MATURE |
| `Std.Http` HTTP/1.1 server and `Std.Async` TCP/UDP (moved into `Std` in 4.31) | YOUNG. **No TLS, HTTP/2 or WebSockets.** Run behind a reverse proxy. |
| Web frameworks (Lithe, LeanIO, Hale) | v0.1, single author |
| Databases (`leansqlite` 0.1, `lean-postgres`) | EXPERIMENTAL. No ORM. |
| C FFI (`@[extern]`) | Works, but the manual calls it "unstable". Reference counting is manual. |
| Rust / Python interop | EXPERIMENTAL (lean-sys, Nerodia) |
| WASM / JS / browser UI | MISSING (officially) |
| Property testing: Plausible | MATURE |
| Verification: `grind`, `omega`, `bv_decide`, `decide` | MATURE |
| `Std.Do` + `mvcgen`→`vcgen` (VCs for monadic `do` code) | EXPERIMENTAL but official. Loop invariants are written by hand. Does not cover `IO` directly. |
| Complexity / cost proofs (Cslib `TimeM`) | RESEARCH. Costs are ticked by hand and not tied to execution. |
| Wall-clock performance proofs | **Not possible.** Only cost *models* can be proven. |
| Debugger | MISSING |

**Trust boundaries:**
- `partial` hides a function's behaviour from proofs.
- `implemented_by` and `extern` can make the running code differ from the model.
- `native_decide` trusts the compiler.
- The running binary trusts the compiler, the C toolchain, the runtime and the FFI.

**Agent tooling:**
- elan / Lake / `lean-toolchain` pinning (releases are monthly, with frequent renames).
- lean-lsp-mcp (MIT; `claude mcp add lean-lsp uvx lean-lsp-mcp`).
- lean-beam.
- Lean REPL / LeanInteract / Pantograph / Kimina server.
- `lake comparator` (in core since 4.35).
- Mathlib: always `lake exe cache get`, and avoid it in apps unless it is needed.

**Windows:** works, but there are problems with spaces in paths (this repo's path has one), linker issues on large projects, and C FFI needing MSYS2 clang. WSL is the lower-friction option.

---

## 3b. Case study: Lean in the "$12 Server Challenge" (the closest template to MakeItLean)

The challenge: implement one small social-media API on SQLite in any language. It is benchmarked on a 1 vCPU / 2 GB server, and the score is the number of concurrent users held for 5 minutes ([repo](https://github.com/arjaythedev/twelve-dollar-server-challenge)).

**lean-derive-hargup ([PR #153](https://github.com/arjaythedev/twelve-dollar-server-challenge/pull/153)).**
- Lean defines the domain and its contract, and C is derived from it.
- Read plans are proven against a Lean model under a *data invariant the server checks*. Example: posts are already stored in feed order, so the feed can be read straight off the B-tree.
- About 280k users, reaching #1 at one point. Its C is tested, not proved.

**lean-verified-soonhokong ([PR #271](https://github.com/arjaythedev/twelve-dollar-server-challenge/pull/271)).** "The handler the theorems are about is the one that runs."
- **Monad-generic core.** The handler is written once, generic over `class Store (m : Type → Type)` (nine operations). The server runs it as `Store IO` (C over SQLite). The proofs run it as `Store Model`, a state monad over the spec's tables (lists of rows). *The proven code and the shipped code are the same Lean.*
- **Spec written from the sources.** `Feed/Spec.lean` and `Feed/Spec/*` are transcribed from SPEC.md, schema.sql and the RFCs (HTTP 9110/9112, JSON 8259, base64url 4648, SHA-256 FIPS 180-4, HMAC 2104, JWT 7515/7519). Test vectors are run with `#guard`.
- **End-to-end theorem.** `runBatch_correct`: on any storage meeting the Lean contract, a batch's answers equal `Spec.batch` of its input bytes. There are 819 theorems (14.8k lines of proofs) against 1.9k lines of Lean code. No `partial` and no `sorry`, and only the standard axioms are used.
- **Proofs license optimizations.**
  - "A batch is a serial execution" lets the transport do group commit with no new proof.
  - The feed-plan theorems let it read the B-tree directly instead of going through the SQL engine.
- **C hot leaves.**
  - 15 functions (HMAC, base64, rendering) are `@[extern]` C, each sitting on a Lean definition that is its spec.
  - `build.sh` runs a self-test comparing every leaf to its Lean definition on 20,000 random inputs, and the C storage against `Store Model` on a random DB.
  - Bugs injected on purpose (a flipped MAC bit, an off-by-one) make the build fail.
  - *Congruence theorems* let the C side choose its own data layout.
- **Audit script.** `check-docs.sh` verifies that no end-to-end theorem rests on an unproved statement, and re-checks every theorem with each leaf made opaque.
- **Explicit trust base.** C storage and transport, SQLite, the Lean compiler, gcc and Linux are documented as trusted and tested, not proved.
- **Results.** About 290k users officially. On equal VMs it held 350k vs 333k for the best C/io_uring entry, at 13.7 µs CPU per request.

**Takeaway.** Performance does not come from Lean being fast. It comes from **proving invariants that make aggressive shortcuts safe**: skipping the query engine, group commit, direct B-tree reads, C leaves. Correctness is kept by end-to-end theorems plus differential self-tests at every unproved boundary. MakeItLean should make this pattern the default.

---

## 4. Synthesis: lessons for MakeItLean

1. **A proof only guarantees "implementation ⊨ spec".** Most of the risk is in the spec. Validate specs before coding:
   - examples or tests drawn from the requirements;
   - Plausible PBT against the spec;
   - non-vacuity: preconditions are satisfiable and the postcondition can actually fail;
   - mutation checks: the spec rejects mutated implementations;
   - human sign-off.
2. **A frozen, human-approved spec plus an external verifier.** Run `lake comparator` with an axiom whitelist, and ban `sorry`, `native_decide`, custom axioms, and unlisted `partial`/`unsafe`/`implemented_by`. Implementer agents cannot write to spec files.
3. **Performance guarantees need an explicit cost model in the spec**, as in the DeepMind paper. Proofs bound *modeled* cost (operation counts, allocations, queries, complexity), not wall-clock time. Benchmarks cover wall-clock time.
4. **Verified core, tested shell.** Use the Cedar pattern for anything Lean does not support well (TLS web, UI, production DBs). The Lean executable model serves as the oracle, and differential testing gates CI.
5. **Every module gets a trust manifest** that records whether each property is *proven*, *tested* or *assumed*.
6. **Separate the roles:** spec author, spec critic, implementer, prover, auditor. Counterexamples and disproofs go back to spec review instead of being "proved around".
7. **Test first, prove second** (arcsin, Cedar). Cheap testing narrows the search. Proof closes the gaps and generalizes.
8. **Shared verified knowledge base** (the DeepMind wiki): reusable lemmas, dead ends and best solutions, so that work across sessions and agents adds up.
9. **Tiered provers:** a frontier agent for structure, `grind`/`omega`/`bv_decide` automation, an optional cheap prover (Leanstral), and an optional commercial back end (Aristotle).
10. **Pin everything and design for churn:** a toolchain pin per project, a CI bump bot, and no Mathlib unless needed.
11. **Monad-generic core** (from §3b): write app logic once, generic over an effect or storage interface. Prove it in a pure model monad and run it in `IO`. This closes most of the "proven model vs shipped code" gap without extraction.
12. **Proof-licensed optimization** (from §3b): the spec states the *simple* semantics (for example, a sort with LIMIT 20). Agents may implement any fast path (B-tree scans, batching, C leaves) as long as they prove it, or for C leaves differentially test it, equal to that semantics.
