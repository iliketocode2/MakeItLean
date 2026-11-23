import LeanKVSol.Base.Properties

/-!
# Ledger spec: reference model and storage layout

A bank ledger of named accounts with balances in whole cents (REQUIREMENTS.md R1–R10b).

* **Reference model.** The state is the list of accounts with their balances, in ascending name
  order. Every command that names accounts is decided by one function, `plan`, which sees the
  ledger only through a balance lookup. `cstep` is the meaning of one command.
* **Storage layout** (R14–R17, §6). The ledger lives in the LeanKV store: key = the account name,
  value = the balance as 8 bytes, least significant first. `dec` says which ledger a store stands
  for, and `pickRef` turns each command into exactly one LeanKV command.
* **Stage 2 theorems.** The balance codec round-trips, and `pickRef_refines`: on every store,
  running the chosen LeanKV command changes the decoded ledger exactly as `cstep` does.
-/

namespace Ledger.Spec
open LeanKV.Spec

/-! ## Names, amounts, limits (R2–R4) -/

/-- English: The largest balance an account may hold, and the largest amount: 2⁶³ − 1 =
9,223,372,036,854,775,807 cents (R3, R4). -/
def maxBalance : Nat := 2 ^ 63 - 1

/-- English: A byte allowed in an account name: an ASCII digit `0`–`9`, upper-case letter `A`–`Z`,
lower-case letter `a`–`z`, or one of `-`, `_`, `.` (R2). -/
def nameByte (b : UInt8) : Bool :=
  (0x30 ≤ b && b ≤ 0x39) || (0x41 ≤ b && b ≤ 0x5A) || (0x61 ≤ b && b ≤ 0x7A) ||
    b == 0x2D || b == 0x5F || b == 0x2E

/-- English: An account name is valid when it is 1 to 64 bytes long and every byte is allowed
(R2). Names are compared byte for byte, so they are case-sensitive. -/
def validName (n : Bytes) : Bool := 1 ≤ n.length && n.length ≤ 64 && n.all nameByte

/-- English: An amount is valid when it is at least 1 cent and at most `maxBalance` (R4). -/
def validAmount (a : Nat) : Bool := 1 ≤ a && a ≤ maxBalance

/-! ## Commands and answers (R6–R10b) -/

/-- English: A Ledger command, generic in the byte-string type of account names (spec: lists;
implementation: arrays). Amounts are whole cents. -/
inductive LCmd (β : Type) where
  /-- English: `open NAME`: create account NAME with balance 0 (R6). -/
  | openAccount (n : β)
  /-- English: `deposit NAME AMOUNT`: add AMOUNT to NAME's balance (R7). -/
  | deposit (n : β) (a : Nat)
  /-- English: `withdraw NAME AMOUNT`: subtract AMOUNT from NAME's balance (R8). -/
  | withdraw (n : β) (a : Nat)
  /-- English: `transfer FROM TO AMOUNT`: move AMOUNT from account FROM to account TO (R9). -/
  | transfer (src dst : β) (a : Nat)
  /-- English: `balance NAME`: answer NAME's balance (R10). -/
  | balance (n : β)
  /-- English: `accounts`: answer every account and its balance, in name order (R10a). -/
  | accounts
  /-- English: `total`: answer the sum of all balances (R10b). -/
  | total
  deriving Repr, DecidableEq

/-- English: Change the byte-string representation of the names inside a command. -/
def LCmd.map {β γ : Type} (f : β → γ) : LCmd β → LCmd γ
  | .openAccount n => .openAccount (f n)
  | .deposit n a => .deposit (f n) a
  | .withdraw n a => .withdraw (f n) a
  | .transfer s d a => .transfer (f s) (f d) a
  | .balance n => .balance (f n)
  | .accounts => .accounts
  | .total => .total

/-- English: Why a command was refused (§3). A refused command changes nothing. -/
inductive LErr where
  /-- English: `BAD_NAME`: a name is not 1–64 allowed bytes (R2). -/
  | badName
  /-- English: `BAD_AMOUNT`: the amount is 0 or more than `maxBalance` (R4). -/
  | badAmount
  /-- English: `ACCOUNT_EXISTS`: `open` of a name that already has an account (R6). -/
  | accountExists
  /-- English: `UNKNOWN_ACCOUNT n`: there is no account named `n`. -/
  | unknownAccount (n : Bytes)
  /-- English: `INSUFFICIENT_FUNDS`: the balance is smaller than the amount taken out (R8, R9). -/
  | insufficientFunds
  /-- English: `BALANCE_LIMIT`: the new balance would exceed `maxBalance` (R7, R9). -/
  | balanceLimit
  /-- English: `SAME_ACCOUNT`: a transfer from an account to itself (R9, D4). -/
  | sameAccount
  deriving Repr, DecidableEq

/-- English: The answer to a command. -/
inductive LResp where
  /-- English: `OK`: `open` or `transfer` succeeded. -/
  | ok
  /-- English: `BALANCE b`: an account's balance (after `deposit`/`withdraw`: the new one). -/
  | balance (b : Nat)
  /-- English: `ACCOUNTS …`: every account and its balance, in ascending name order. -/
  | accounts (l : List (Bytes × Nat))
  /-- English: `TOTAL t`: the sum of all balances. -/
  | total (t : Nat)
  /-- English: `ERR e`: the command was refused for reason `e` and changed nothing. -/
  | err (e : LErr)
  deriving Repr, DecidableEq

/-! ## The reference state -/

/-- English: The reference state: every account with its balance, as (name, balance) pairs in
ascending name order (bytewise, as LeanKV orders keys). The empty list is the new ledger. -/
abbrev LState := List (Bytes × Nat)

/-- English: The balance of account `n`, or nothing if there is no such account. -/
def LState.bal (s : LState) (n : Bytes) : Option Nat :=
  (s.find? (fun p => p.1 == n)).map Prod.snd

/-- English: Set account `n`'s balance to `v`, creating the account if it is missing, and keeping
the list in name order. (The same walk as LeanKV's `Store.insert`.) -/
def LState.set : LState → Bytes → Nat → LState
  | [], k, v => [(k, v)]
  | (k', v') :: rest, k, v =>
    if bytesLt k k' then (k, v) :: (k', v') :: rest
    else if k == k' then (k, v) :: rest
    else (k', v') :: LState.set rest k v

/-- English: The total money in the ledger: the sum of all balances (R5). -/
def LState.total (s : LState) : Nat := (s.map Prod.snd).sum

/-! ## The decision for one command -/

/-- English: What a command does, decided from balance lookups alone. -/
inductive Plan where
  /-- English: Refuse with this reason; nothing changes. -/
  | refuse (e : LErr)
  /-- English: Answer this, changing nothing. -/
  | answer (r : LResp)
  /-- English: Set each listed account to the listed balance, in order, then answer `r`. -/
  | write (ups : List (Bytes × Nat)) (r : LResp)
  /-- English: Answer the list of all accounts (`accounts`); nothing changes. -/
  | listAll
  /-- English: Answer the total of all balances (`total`); nothing changes. -/
  | sumAll

/-- English: The rules of §3, with errors checked in the order the table lists them. `look n` is
the balance of account `n`, or nothing if there is no such account.
* `open n`: bad name; account exists; otherwise create `n` with 0 and answer OK.
* `deposit n a`: bad name; bad amount; unknown account; new balance over the maximum; otherwise
  set the new balance and answer it.
* `withdraw n a`: bad name; bad amount; unknown account; balance below `a`; otherwise set the new
  balance and answer it.
* `transfer f t a`: bad name (either); same account; bad amount; unknown `f`; unknown `t`; `f`'s
  balance below `a`; `t`'s new balance over the maximum; otherwise set both balances in one step
  and answer OK.
* `balance n`: bad name; unknown account; otherwise answer the balance.
* `accounts`, `total`: answer from the whole ledger. -/
def plan (look : Bytes → Option Nat) : LCmd Bytes → Plan
  | .openAccount n =>
    if !validName n then .refuse .badName
    else match look n with
      | some _ => .refuse .accountExists
      | none => .write [(n, 0)] .ok
  | .deposit n a =>
    if !validName n then .refuse .badName
    else if !validAmount a then .refuse .badAmount
    else match look n with
      | none => .refuse (.unknownAccount n)
      | some b => if b + a ≤ maxBalance then .write [(n, b + a)] (.balance (b + a))
                  else .refuse .balanceLimit
  | .withdraw n a =>
    if !validName n then .refuse .badName
    else if !validAmount a then .refuse .badAmount
    else match look n with
      | none => .refuse (.unknownAccount n)
      | some b => if a ≤ b then .write [(n, b - a)] (.balance (b - a))
                  else .refuse .insufficientFunds
  | .transfer f t a =>
    if !(validName f && validName t) then .refuse .badName
    else if f = t then .refuse .sameAccount
    else if !validAmount a then .refuse .badAmount
    else match look f, look t with
      | none, _ => .refuse (.unknownAccount f)
      | some _, none => .refuse (.unknownAccount t)
      | some bf, some bt =>
        if a ≤ bf then
          if bt + a ≤ maxBalance then .write [(f, bf - a), (t, bt + a)] .ok
          else .refuse .balanceLimit
        else .refuse .insufficientFunds
  | .balance n =>
    if !validName n then .refuse .badName
    else match look n with
      | none => .refuse (.unknownAccount n)
      | some b => .answer (.balance b)
  | .accounts => .listAll
  | .total => .sumAll

/-- English: Apply a list of balance settings, in order. -/
def LState.setAll (s : LState) (ups : List (Bytes × Nat)) : LState :=
  ups.foldl (fun s p => s.set p.1 p.2) s

/-- English: The reference meaning of one command: the new ledger and the answer. A refused
command changes nothing and answers `ERR`; a write applies all of its settings at once. -/
def cstep (s : LState) (c : LCmd Bytes) : LState × LResp :=
  match plan s.bal c with
  | .refuse e => (s, .err e)
  | .answer r => (s, r)
  | .write ups r => (s.setAll ups, r)
  | .listAll => (s, .accounts s)
  | .sumAll => (s, .total s.total)

/-- English: Run commands one after another from ledger `s`: the final ledger and every answer,
in order. -/
def lrun (s : LState) : List (LCmd Bytes) → LState × List LResp
  | [] => (s, [])
  | c :: cs =>
    let (s', r) := cstep s c
    let (s'', rs) := lrun s' cs
    (s'', r :: rs)

/-! ## Storage layout in LeanKV (§6) -/

/-- English: A balance stored as 8 bytes, least significant first. -/
def u64le (v : Nat) : Bytes :=
  [(v % 256).toUInt8, (v / 256 % 256).toUInt8, (v / 256 ^ 2 % 256).toUInt8,
   (v / 256 ^ 3 % 256).toUInt8, (v / 256 ^ 4 % 256).toUInt8, (v / 256 ^ 5 % 256).toUInt8,
   (v / 256 ^ 6 % 256).toUInt8, (v / 256 ^ 7 % 256).toUInt8]

/-- English: Read a little-endian number (least significant byte first). -/
def decodeU64 : Bytes → Nat
  | [] => 0
  | b :: bs => b.toNat + 256 * decodeU64 bs

/-- English: Read a stored balance: the number in its first 8 bytes, least significant first. -/
def decodeBal (v : Bytes) : Nat := decodeU64 (v.take 8)

/-- English: The ledger a LeanKV store stands for: one account per key, with the stored balance,
in the store's (ascending) key order. -/
def dec (st : Store) : LState := st.map (fun p => (p.1, decodeBal p.2))

/-- English: The balance of account `n` in a LeanKV store, or nothing if the key is absent. -/
def balOf (st : Store) (n : Bytes) : Option Nat := (st.lookup n).map decodeBal

/-- English: The LeanKV command that sets the listed accounts' balances: a single `put` for one
account, and one atomic `batch` of puts otherwise (a transfer's two accounts). -/
def writeCmd : List (Bytes × Nat) → Cmd Bytes
  | [] => .batch []
  | [p] => .put p.1 (u64le p.2)
  | p :: q :: r => .batch ((p :: q :: r).map (fun x => .put x.1 (u64le x.2)))

/-- English: The LeanKV read used for commands that change nothing: an empty scan. -/
def readNothing : Cmd Bytes := .scan [] .unbounded 0

/-- English: Translate a command into one LeanKV command, given a balance lookup: a write plan
becomes `writeCmd`, everything else becomes a read that changes nothing. -/
def pickWith (look : Bytes → Option Nat) (c : LCmd Bytes) : Cmd Bytes :=
  match plan look c with
  | .write ups _ => writeCmd ups
  | _ => readNothing

/-- English: The reference translation of a command into exactly one LeanKV command on store
`st`, deciding from the balances stored in `st`. -/
def pickRef (st : Store) (c : LCmd Bytes) : Cmd Bytes := pickWith (balOf st) c

/-- English: Run Ledger commands through LeanKV from store `st`, each as its `pickRef` command. -/
def kvRun (st : Store) : List (LCmd Bytes) → Store
  | [] => st
  | c :: cs => kvRun (step st (pickRef st c)).1 cs

/-! ## Spec validation (Stage 2): the layout and translation mean what the model says -/

/-- English: A number read from a list of `l` bytes is below 256 to the power `l`. -/
theorem decodeU64_lt (l : Bytes) : decodeU64 l < 256 ^ l.length := by
  induction l with
  | nil => simp [decodeU64]
  | cons b bs ih =>
    simp only [decodeU64, List.length_cons, Nat.pow_succ]
    have := b.toNat_lt
    have : 256 * decodeU64 bs + 256 ≤ 256 * 256 ^ bs.length := by
      have := Nat.mul_le_mul_left 256 (Nat.succ_le_of_lt ih); omega
    omega

/-- English: Every stored balance reads back as a number below 2⁶⁴. -/
theorem decodeBal_lt (v : Bytes) : decodeBal v < 2 ^ 64 := by
  have h := decodeU64_lt (v.take 8)
  have hl : (v.take 8).length ≤ 8 := by simp [List.length_take]; omega
  have : 256 ^ (v.take 8).length ≤ 256 ^ 8 := Nat.pow_le_pow_right (by decide) hl
  unfold decodeBal; omega

/-- English: Reading back a stored balance gives the balance, for every balance below 2⁶⁴. -/
theorem decodeBal_u64le {v : Nat} (h : v < 2 ^ 64) : decodeBal (u64le v) = v := by
  simp only [decodeBal, u64le, List.take, decodeU64, UInt8.toNat_ofNat', Nat.toUInt8]
  simp
  omega

/-- English: A stored balance is exactly 8 bytes long. -/
theorem u64le_length (v : Nat) : (u64le v).length = 8 := rfl

/-- English: A valid name is a valid LeanKV key. -/
theorem validName_validKey {n : Bytes} (h : validName n = true) : validKey n = true := by
  simp only [validName, Bool.and_eq_true, decide_eq_true_eq] at h
  simp only [validKey, Bool.and_eq_true, decide_eq_true_eq]
  simp only [maxKeyLen]; omega

/-- English: A stored balance is a valid LeanKV value. -/
theorem validValue_u64le (v : Nat) : validValue (u64le v) = true := by
  simp [validValue, u64le, maxValueLen]

/-- English: Looking up an account in the decoded ledger is looking up its key in the store. -/
theorem bal_dec (st : Store) (n : Bytes) : (dec st).bal n = balOf st n := by
  induction st with
  | nil => simp [dec, LState.bal, balOf, Store.lookup]
  | cons q rest ih =>
    obtain ⟨k, v⟩ := q
    by_cases hk : k = n
    · subst hk; simp [dec, LState.bal, balOf, lookup_cons]
    · have e : (dec ((k, v) :: rest)).bal n = (dec rest).bal n := by
        simp [dec, LState.bal, hk]
      rw [e, ih]; simp [balOf, lookup_cons, hk]

/-- English: Decoding a store after a LeanKV insert is setting the balance in the decoded ledger. -/
theorem dec_insert (st : Store) (k v : Bytes) :
    dec (st.insert k v) = (dec st).set k (decodeBal v) := by
  induction st with
  | nil => simp [dec, Store.insert, LState.set]
  | cons q rest ih =>
    obtain ⟨k', v'⟩ := q
    simp only [Store.insert, LState.set, dec, List.map_cons] at ih ⊢
    by_cases h1 : bytesLt k k' = true
    · simp [h1]
    · by_cases h2 : (k == k') = true
      · simp [h1, h2]
      · simp only [h1, h2, Bool.false_eq_true, ↓reduceIte, List.map_cons, ih]

/-- English: **The successful writes, exactly.** A command makes a write plan only in these four
cases, and then sets exactly these balances and gives exactly this answer:
* `open n` with a valid name and no account `n`: set `n` to 0, answer OK;
* `deposit n a` with a valid name and amount, account `n` holding `b`, and `b + a ≤ maxBalance`:
  set `n` to `b + a`, answer that balance;
* `withdraw n a` with a valid name and amount, account `n` holding `b ≥ a`: set `n` to `b − a`,
  answer that balance;
* `transfer f t a` with two valid, different names, a valid amount, `f` holding `bf ≥ a` and `t`
  holding `bt` with `bt + a ≤ maxBalance`: set `f` to `bf − a` and `t` to `bt + a`, answer OK. -/
theorem plan_write_cases {look : Bytes → Option Nat} {c : LCmd Bytes} {ups : List (Bytes × Nat)}
    {r : LResp} (h : plan look c = .write ups r) :
    (∃ n, c = .openAccount n ∧ validName n = true ∧ look n = none ∧ ups = [(n, 0)] ∧ r = .ok) ∨
    (∃ n a b, c = .deposit n a ∧ validName n = true ∧ validAmount a = true ∧ look n = some b ∧
      b + a ≤ maxBalance ∧ ups = [(n, b + a)] ∧ r = .balance (b + a)) ∨
    (∃ n a b, c = .withdraw n a ∧ validName n = true ∧ validAmount a = true ∧ look n = some b ∧
      a ≤ b ∧ ups = [(n, b - a)] ∧ r = .balance (b - a)) ∨
    (∃ f t a bf bt, c = .transfer f t a ∧ validName f = true ∧ validName t = true ∧ f ≠ t ∧
      validAmount a = true ∧ look f = some bf ∧ look t = some bt ∧ a ≤ bf ∧
      bt + a ≤ maxBalance ∧ ups = [(f, bf - a), (t, bt + a)] ∧ r = .ok) := by
  cases c with
  | openAccount n =>
    simp only [plan] at h
    split at h
    · cases h
    · rename_i h1
      split at h
      · cases h
      · rename_i hn; cases h
        exact .inl ⟨n, rfl, by simpa using h1, hn, rfl, rfl⟩
  | deposit n a =>
    simp only [plan] at h
    split at h
    · cases h
    · rename_i h1
      split at h
      · cases h
      · rename_i h2
        split at h
        · cases h
        · rename_i b hb
          split at h
          · rename_i h3; cases h
            exact .inr (.inl ⟨n, a, b, rfl, by simpa using h1, by simpa using h2, hb, h3, rfl, rfl⟩)
          · cases h
  | withdraw n a =>
    simp only [plan] at h
    split at h
    · cases h
    · rename_i h1
      split at h
      · cases h
      · rename_i h2
        split at h
        · cases h
        · rename_i b hb
          split at h
          · rename_i h3; cases h
            exact .inr (.inr (.inl ⟨n, a, b, rfl, by simpa using h1, by simpa using h2, hb, h3,
              rfl, rfl⟩))
          · cases h
  | transfer f t a =>
    simp only [plan] at h
    split at h
    · cases h
    · rename_i h1
      split at h
      · cases h
      · rename_i hft
        split at h
        · cases h
        · rename_i h2
          split at h
          · cases h
          · cases h
          · rename_i bf bt hf ht
            split at h
            · rename_i h3
              split at h
              · rename_i h4; cases h
                simp only [Bool.not_eq_true', Bool.and_eq_false_iff] at h1
                refine .inr (.inr (.inr ⟨f, t, a, bf, bt, rfl, ?_, ?_, hft, by simpa using h2, hf,
                  ht, h3, h4, rfl, rfl⟩)) <;> cases hf' : validName f <;> cases ht' : validName t <;>
                  simp_all
              · cases h
            · cases h
  | balance n =>
    simp only [plan] at h
    split at h
    · cases h
    · split at h <;> cases h
  | accounts => simp [plan] at h
  | total => simp [plan] at h

/-- English: Every balance a write plan sets is for a valid name and at most `B`, and a plan sets
at most two accounts, provided every looked-up balance is at most `B` and `B ≥ maxBalance`. -/
theorem plan_write_ok {look : Bytes → Option Nat} {B : Nat} (hB : maxBalance ≤ B)
    (hlook : ∀ n b, look n = some b → b ≤ B)
    {c : LCmd Bytes} {ups : List (Bytes × Nat)} {r : LResp} (h : plan look c = .write ups r) :
    (∀ p ∈ ups, validName p.1 = true ∧ p.2 ≤ B) ∧ ups.length ≤ 2 := by
  rcases plan_write_cases h with ⟨n, -, hn, -, rfl, -⟩ | ⟨n, a, b, -, hn, -, -, hab, rfl, -⟩ |
    ⟨n, a, b, -, hn, -, hb, -, rfl, -⟩ | ⟨f, t, a, bf, bt, -, hf, ht, -, -, hbf, -, -, hbt, rfl, -⟩
  · simp [hn]
  · simp [hn]; omega
  · have := hlook n b hb; simp [hn]; omega
  · have := hlook f bf hbf; simp [hf, ht]; omega

/-- English: Running the LeanKV command for a write plan changes the decoded ledger by setting
each listed balance, in order (one `put`, or one atomic `batch`). -/
theorem step_writeCmd (st : Store) (ups : List (Bytes × Nat))
    (hv : ∀ p ∈ ups, validName p.1 = true ∧ p.2 ≤ 2 ^ 64 - 1) (hl : ups.length ≤ 2) :
    dec (step st (writeCmd ups)).1 = (dec st).setAll ups := by
  match ups, hv, hl with
  | [], _, _ => simp [writeCmd, step, runBatch, validBatch, LState.setAll]
  | [p], hv, _ =>
    have h1 := hv p (by simp)
    simp only [writeCmd, step_put, validName_validKey h1.1, validValue_u64le, Bool.and_self,
      ↓reduceIte, LState.setAll, List.foldl_cons, List.foldl_nil, dec_insert, decodeBal_u64le (by omega : p.2 < 2 ^ 64)]
  | [p, q], hv, _ =>
    have h1 := hv p (by simp)
    have h2 := hv q (by simp)
    have hb : validBatch [.put p.1 (u64le p.2), .put q.1 (u64le q.2)] = true := by
      have k1 := validName_validKey h1.1
      have k2 := validName_validKey h2.1
      have n1 := h1.1
      have n2 := h2.1
      simp only [validName, validKey, Bool.and_eq_true, decide_eq_true_eq] at k1 k2 n1 n2
      simp only [validBatch, List.all_cons, List.all_nil, WriteOp.valid, WriteOp.size,
        validValue_u64le, List.map_cons, List.map_nil, List.sum_cons, List.sum_nil, Bool.and_true,
        Bool.and_eq_true, decide_eq_true_eq, validKey] at k1 k2 ⊢
      simp only [List.length_cons, List.length_nil, u64le_length, maxBatchOps, maxBatchBytes,
        maxKeyLen] at k1 k2 ⊢
      omega
    simp only [writeCmd, List.map_cons, List.map_nil, step, runBatch, hb, ↓reduceIte,
      List.foldl_cons, List.foldl_nil, WriteOp.apply, LState.setAll, dec_insert,
      decodeBal_u64le (by omega : p.2 < 2 ^ 64), decodeBal_u64le (by omega : q.2 < 2 ^ 64)]
  | _ :: _ :: _ :: _, _, hl => simp at hl

/-- English: **Refinement.** On every store, running the translated LeanKV command changes the
decoded ledger exactly as the reference model does. -/
theorem pickRef_refines (st : Store) (c : LCmd Bytes) :
    dec (step st (pickRef st c)).1 = (cstep (dec st) c).1 := by
  have hb : (dec st).bal = balOf st := funext (bal_dec st)
  have hlook : ∀ n b, balOf st n = some b → b ≤ 2 ^ 64 - 1 := by
    intro n b h
    simp only [balOf, Option.map_eq_some_iff] at h
    obtain ⟨v, _, rfl⟩ := h
    have := decodeBal_lt v; omega
  unfold pickRef pickWith cstep
  rw [hb]
  cases hp : plan (balOf st) c with
  | write ups r =>
    obtain ⟨hv, hl⟩ := plan_write_ok (by decide) hlook hp
    exact step_writeCmd st ups hv hl
  | refuse e => simp [readNothing, step, validLower, Upper.valid]
  | answer r => simp [readNothing, step, validLower, Upper.valid]
  | listAll => simp [readNothing, step, validLower, Upper.valid]
  | sumAll => simp [readNothing, step, validLower, Upper.valid]

/-- English: **Refinement over whole runs.** Running any commands through LeanKV from a store that
stands for ledger `s` gives a store that stands for the ledger the model reaches. In particular,
from the empty store (a new ledger directory) the stored ledger is always a model-reachable one. -/
theorem kvRun_refines (cs : List (LCmd Bytes)) {st : Store} {s : LState} (h : dec st = s) :
    dec (kvRun st cs) = (lrun s cs).1 := by
  induction cs generalizing st s with
  | nil => simp [kvRun, lrun, h]
  | cons c cs ih =>
    simp only [kvRun, lrun]
    exact ih (by rw [pickRef_refines, h])

end Ledger.Spec
