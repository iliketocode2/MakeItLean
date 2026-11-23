#!/usr/bin/env bash
# Stage 5 boundary tests for the `ledger` CLI on real files (REQUIREMENTS.md §3, R14).
# Usage: tests/cli_test.sh   (from examples/ledger/impl, after `lake build ledgerCli`)
set -u
cd "$(dirname "$0")/.."
BIN="$PWD/.lake/build/bin/ledger"
D="$(mktemp -d)"
trap 'rm -rf "$D"' EXIT
pass=0; fail=0

# expect <expected stdout> <expected exit code> <args…>
expect() {
  local want="$1" wcode="$2"; shift 2
  local got code
  got="$("$BIN" "$@")"; code=$?
  if [[ "$got" == "$want" && "$code" == "$wcode" ]]; then pass=$((pass+1))
  else fail=$((fail+1)); echo "FAIL: ledger $* -> '$got' ($code), want '$want' ($wcode)"; fi
}

L="$D/l1"
MAX=9223372036854775807
# The 18-step example of §3, in order.
expect "OK" 0 "$L" open alice
expect "ERR ACCOUNT_EXISTS" 1 "$L" open alice
expect "OK" 0 "$L" open bob
expect "BALANCE 1000" 0 "$L" deposit alice 1000
expect "OK" 0 "$L" transfer alice bob 300
expect "BALANCE 700" 0 "$L" balance alice
expect "BALANCE 300" 0 "$L" balance bob
expect "ERR INSUFFICIENT_FUNDS" 1 "$L" transfer bob alice 301
expect "ERR UNKNOWN_ACCOUNT carol" 1 "$L" transfer alice carol 1
expect "ERR BAD_AMOUNT" 1 "$L" transfer alice bob 0
expect "ERR SAME_ACCOUNT" 1 "$L" transfer alice alice 5
expect "BALANCE 0" 0 "$L" withdraw bob 300
expect "ERR INSUFFICIENT_FUNDS" 1 "$L" withdraw bob 1
expect "ERR UNKNOWN_ACCOUNT carol" 1 "$L" deposit carol 5
expect "ERR BAD_NAME" 1 "$L" open bad/name
expect "ERR BALANCE_LIMIT" 1 "$L" deposit alice $MAX
expect "ACCOUNTS 2 alice 700 bob 0" 0 "$L" accounts
expect "TOTAL 700" 0 "$L" total

# Persistence across runs and refused commands changing nothing (R11, R15).
expect "BALANCE 700" 0 "$L" balance alice
expect "ERR UNKNOWN_ACCOUNT zed" 1 "$L" transfer zed alice 5
expect "ERR UNKNOWN_ACCOUNT zed" 1 "$L" transfer alice zed 5
expect "ACCOUNTS 2 alice 700 bob 0" 0 "$L" accounts

# Limits: amounts 0, 1, MAX, MAX+1; names of 0, 1, 64, 65 bytes; allowed characters.
L="$D/l2"
N64="$(printf 'a%.0s' $(seq 64))"; N65="$(printf 'a%.0s' $(seq 65))"
expect "OK" 0 "$L" open x
expect "ERR BAD_AMOUNT" 1 "$L" deposit x 0
expect "BALANCE 1" 0 "$L" deposit x 1
expect "ERR BALANCE_LIMIT" 1 "$L" deposit x $MAX
expect "BALANCE 0" 0 "$L" withdraw x 1
expect "BALANCE $MAX" 0 "$L" deposit x $MAX
expect "ERR BAD_AMOUNT" 1 "$L" deposit x 9223372036854775808
expect "ERR BAD_AMOUNT" 1 "$L" deposit x 99999999999999999999999999
expect "OK" 0 "$L" open y
# Error order: insufficient funds is checked before the balance limit.
expect "ERR INSUFFICIENT_FUNDS" 1 "$L" transfer y x 1
expect "BALANCE 5" 0 "$L" deposit y 5
expect "ERR BALANCE_LIMIT" 1 "$L" transfer y x 1
expect "OK" 0 "$L" transfer x y $((MAX - 5))
expect "BALANCE 5" 0 "$L" balance x
expect "BALANCE $MAX" 0 "$L" balance y
expect "TOTAL 9223372036854775812" 0 "$L" total
expect "ERR BAD_NAME" 1 "$L" open ""
expect "OK" 0 "$L" open z
expect "OK" 0 "$L" open "$N64"
expect "ERR BAD_NAME" 1 "$L" open "$N65"
expect "OK" 0 "$L" open "A-b_c.9"
expect "ERR BAD_NAME" 1 "$L" open "a b"
expect "ERR BAD_NAME" 1 "$L" open "é"
expect "ERR BAD_NAME" 1 "$L" balance "$N65"
expect "ERR BAD_NAME" 1 "$L" transfer x "$N65" 0
expect "ERR SAME_ACCOUNT" 1 "$L" transfer x x 0
expect "ERR BAD_AMOUNT" 1 "$L" transfer x y 0
# Bytewise order: upper case before lower case; totals can exceed MAX across accounts.
L="$D/l3"
expect "OK" 0 "$L" open b
expect "OK" 0 "$L" open B
expect "OK" 0 "$L" open a
expect "BALANCE $MAX" 0 "$L" deposit a $MAX
expect "BALANCE $MAX" 0 "$L" deposit b $MAX
expect "ACCOUNTS 3 B 0 a $MAX b $MAX" 0 "$L" accounts
expect "TOTAL 18446744073709551614" 0 "$L" total

# Usage errors (exit 2): unknown command, wrong arity, non-digit amounts.
U="$(./.lake/build/bin/ledger 2>/dev/null)"
expect "$U" 2
expect "$U" 2 "$L"
expect "$U" 2 "$L" frobnicate
expect "$U" 2 "$L" open
expect "$U" 2 "$L" open a b
expect "$U" 2 "$L" deposit a
expect "$U" 2 "$L" deposit a -5
expect "$U" 2 "$L" deposit a +5
expect "$U" 2 "$L" deposit a 12.50
expect "$U" 2 "$L" deposit a ""
expect "$U" 2 "$L" deposit a "1 2"
expect "$U" 2 "$L" transfer a b
expect "$U" 2 "$L" accounts x
[[ "$U" == "ERR USAGE"* ]] && pass=$((pass+1)) || { fail=$((fail+1)); echo "FAIL: usage text"; }

# Corruption: a valid record after garbage makes the ledger refuse to open (R17, exit 3)
# without changing the file.
L="$D/l4"
"$BIN" "$L" open a >/dev/null; "$BIN" "$L" deposit a 5 >/dev/null
cp "$L/leankv.log" "$D/good.log"
python3 - "$L/leankv.log" <<'PY'
import sys
p = sys.argv[1]
b = bytearray(open(p, 'rb').read())
b[len(b) // 4] ^= 0xFF          # damage the first record; the second stays valid
open(p, 'wb').write(bytes(b))
PY
before="$(sha256sum < "$L/leankv.log")"
out="$("$BIN" "$L" balance a)"; code=$?
after="$(sha256sum < "$L/leankv.log")"
if [[ "$out" == "ERR CORRUPT"* && "$code" == 3 && "$before" == "$after" ]]; then pass=$((pass+1))
else fail=$((fail+1)); echo "FAIL: corruption -> '$out' ($code), file changed: $([[ $before != $after ]] && echo yes || echo no)"; fi

# Torn tail: cutting the last record short drops it silently (R17).
cp "$D/good.log" "$L/leankv.log"
truncate -s -3 "$L/leankv.log"
expect "BALANCE 0" 0 "$L" balance a
expect "BALANCE 2" 0 "$L" deposit a 2

# I/O error: the directory cannot be created (exit 4).
out="$("$BIN" /proc/ledger-cannot-exist open a)"; code=$?
if [[ "$out" == "ERR IO"* && "$code" == 4 ]]; then pass=$((pass+1))
else fail=$((fail+1)); echo "FAIL: I/O error -> '$out' ($code)"; fi

echo "cli_test: $pass passed, $fail failed"
[[ $fail == 0 ]]
