#!/usr/bin/env bash
# Stage 5 boundary tests for the CLI on real files: every worked example, every error, every
# limit in REQUIREMENTS.md (proofs do not cover parsing, printing or exit codes).
# Usage: tests/cli_test.sh   (from impl/, after `lake build counterCli`)
set -u
cd "$(dirname "$0")/.."
BIN="$PWD/.lake/build/bin/counter"
D="$(mktemp -d)"
trap 'rm -rf "$D"' EXIT
pass=0; fail=0

# expect <expected stdout> <expected exit code> <args…>
expect() {
  local want="$1" wcode="$2"; shift 2
  local got code
  got="$("$BIN" "$@")"; code=$?
  if [[ "$got" == "$want" && "$code" == "$wcode" ]]; then pass=$((pass+1))
  else fail=$((fail+1)); echo "FAIL: $* -> '$got' ($code), want '$want' ($wcode)"; fi
}

S="$D/s1"
# Worked examples (mirror the spec's #guard lines in Counter/Spec/Properties.lean).
expect "VALUE 1" 0 "$S" incr a
expect "VALUE 2" 0 "$S" incr a
expect "VALUE 2" 0 "$S" get a
expect "VALUE 0" 0 "$S" get b
# Limits: names of 64 and 65 bytes.
N64="$(printf 'a%.0s' $(seq 64))"; N65="$(printf 'a%.0s' $(seq 65))"
expect "VALUE 1" 0 "$S" incr "$N64"
expect "ERR" 1 "$S" incr "$N65"
# Usage errors.
expect "usage: counter <dir> incr|get <name> | counter <dir> serve" 2 "$S" frobnicate a
expect "usage: counter <dir> incr|get <name> | counter <dir> serve" 2 "$S"
# Persistence across runs (each run reopens the store from disk).
expect "VALUE 2" 0 "$S" get a

echo "cli_test: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
