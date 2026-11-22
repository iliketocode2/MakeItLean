# AppName — Requirements (Stage 0, DRAFT for approval)

> Stage 0 of the MakeItLean workflow (`agents/AGENTS.md`). Plain English only; every requirement
> gets an ID (R1, R2, …) that the Lean spec will cite. Mark open questions **[DECIDE]**.
> Do not write the Lean spec until the user approves this file.

## 1. What it is
<one paragraph>

## 2. Data model
- **R1.** …

## 3. Operations
| ID | Operation | Meaning | Example |
|---|---|---|---|

## 4. Durability
AppName keeps its state in the LeanKV store (the substrate). Every acknowledged command survives a
crash; after any crash the state is exactly the acknowledged commands, plus possibly the one in
flight, applied in full (inherited from LeanKV's `substrate_crash_consistent`).

## 5. Storage layout
How the app's state is laid out as LeanKV keys and values.

## 6. What will be proven vs. tested vs. trusted

## 7. Non-goals
