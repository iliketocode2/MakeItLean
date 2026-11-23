# AppName — Requirements (Stage 0, DRAFT for approval)

> Stage 0 of the MakeItLean workflow (`agents/AGENTS.md`). Plain English only; every requirement
> gets an ID (R1, R2, …) that the Lean spec will cite. Mark open questions **[DECIDE]**.
> Do not write the Lean spec until the user approves this file.

## 1. What it is
<one paragraph>

## 2. Data model
- **R1.** …

## 3. Operations
| ID | Operation | On success | Errors, checked in this order |
|---|---|---|---|

When several errors apply to one command, the **first** in its list is reported. A refused command
changes nothing.

### Worked examples (each becomes a `#guard` in `Spec/Properties.lean`)
Starting from the empty state, run in order:

| # | Command | Answer |
|---|---|---|

## 3a. Invariants (properties over sequences of commands, proven in `Spec/Properties.lean`)
- **Scope:** state each invariant for the reference model starting from the empty state, through
  any sequence of commands. The decoded store obeys it because the app only writes stores through
  the proven translation (arbitrary bytes from other writers are out of scope; say so in §6).
- **R…** All-or-nothing: a refused command changes nothing; a command changes only what it names.
- **R…** Bounds: every stored number stays within its stated limit (say what happens at the limit).
- **R…** Conservation or other whole-state properties (for example, totals), if the app has them.

## 4. Durability
AppName keeps its state in the LeanKV store (the substrate). Every acknowledged command survives a
crash; after any crash the state is exactly the acknowledged commands, plus possibly the one in
flight, applied in full (`<App>Impl.crash_consistent`: LeanKV's `app_crash_consistent` applied to the app).

## 5. Storage layout
How the app's state is laid out as LeanKV keys and values.

## 6. What will be proven vs. tested vs. trusted

## 7. Non-goals
