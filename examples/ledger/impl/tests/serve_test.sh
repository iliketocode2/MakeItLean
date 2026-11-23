#!/usr/bin/env bash
# Serve mode (R18) and the oracle (R19): generator coverage, the differential test of serve
# against the frozen model (V1), and serve's startup and stopping rules on real files.
# Usage: tests/serve_test.sh   (from examples/ledger/impl, after `lake build ledgerCli ledgerOracle`)
set -u
cd "$(dirname "$0")/.."
B="$PWD/.lake/build/bin"
D="$(mktemp -d)"
trap 'rm -rf "$D"' EXIT
pass=0; fail=0
ok() { if [[ "$1" == 0 ]]; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL: $2"; fi; }

# V1: serve against the model, at least 30 runs x 200 commands, with a generator that reaches
# every command, error and limit.
python3 tests/gen_coverage.py 30 200 1; ok $? "generator coverage"
python3 -I ../../../tools/difftest.py --sut "$B/ledger {dir} serve" --oracle "$B/ledger-oracle" \
  --gen tests/gen_commands.py --runs 30 --length 200 --seed 1; ok $? "difftest serve vs oracle (seed 1)"
python3 -I ../../../tools/difftest.py --sut "$B/ledger {dir} serve" --oracle "$B/ledger-oracle" \
  --gen tests/gen_commands.py --runs 30 --length 200 --seed 2; ok $? "difftest serve vs oracle (seed 2)"

# Serve: answers flushed per line, ERR USAGE continues, end of input exits 0, state persists.
out="$(printf 'open a\n\nbogus\ndeposit a 5\n' | "$B/ledger" "$D/s1" serve)"; code=$?
[[ "$out" == $'OK\nERR USAGE\nERR USAGE\nBALANCE 5' && $code == 0 ]]; ok $? "serve basics -> '$out' ($code)"
out="$(printf 'balance a\ntotal' | "$B/ledger" "$D/s1" serve)"; code=$?
[[ "$out" == $'BALANCE 5\nTOTAL 5' && $code == 0 ]]; ok $? "serve persistence, last line without newline -> '$out' ($code)"
out="$(printf '' | "$B/ledger" "$D/s1" serve)"; code=$?
[[ "$out" == "" && $code == 0 ]]; ok $? "serve on empty input -> '$out' ($code)"
# The CLI still sees the same ledger.
out="$("$B/ledger" "$D/s1" balance a)"; code=$?
[[ "$out" == "BALANCE 5" && $code == 0 ]]; ok $? "CLI after serve -> '$out' ($code)"
# `serve` with other words is still a usage error of the CLI (exit 2), as before v3.
out="$("$B/ledger" "$D/s1" serve x)"; code=$?
[[ "$out" == "ERR USAGE"* && $code == 2 ]]; ok $? "serve x -> ($code)"
out="$("$B/ledger" serve)"; code=$?
[[ "$out" == "ERR USAGE"* && $code == 2 ]]; ok $? "ledger serve (no dir) -> ($code)"

# Corrupt store: ERR CORRUPT offset p, exit 3, before reading any line, no file changed (R17).
"$B/ledger" "$D/c" open a >/dev/null; "$B/ledger" "$D/c" deposit a 5 >/dev/null
python3 - "$D/c/leankv.log" <<'PY'
import sys
p = sys.argv[1]
b = bytearray(open(p, 'rb').read())
b[len(b) // 4] ^= 0xFF
open(p, 'wb').write(bytes(b))
PY
before="$(sha256sum < "$D/c/leankv.log")"
out="$(printf 'open b\n' | "$B/ledger" "$D/c" serve)"; code=$?
after="$(sha256sum < "$D/c/leankv.log")"
[[ "$out" =~ ^ERR\ CORRUPT\ offset\ [0-9]+$ && $code == 3 && "$before" == "$after" ]]; ok $? "serve on corrupt store -> '$out' ($code)"

# The store cannot be opened: one line starting with ERR IO, exit 4.
out="$(printf 'open a\n' | "$B/ledger" /proc/ledger-cannot-exist serve)"; code=$?
[[ "$out" == "ERR IO"* && "$out" != *$'\n'* && $code == 4 ]]; ok $? "serve I/O error at open -> '$out' ($code)"

# The oracle uses no files and starts from the empty ledger.
out="$(printf 'accounts\nopen a\naccounts\nopen\n' | "$B/ledger-oracle")"; code=$?
[[ "$out" == $'ACCOUNTS 0\nOK\nACCOUNTS 1 a 0\nERR USAGE' && $code == 0 ]]; ok $? "oracle -> '$out' ($code)"

echo "serve_test: $pass passed, $fail failed"
[[ $fail == 0 ]]
