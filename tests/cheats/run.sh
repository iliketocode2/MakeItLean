#!/usr/bin/env bash
# The cheat suite (Phase 6 W0.3): every known way to get a false AUDIT PASSED, each of which
# `mil audit` must reject for the expected reason.
#
#   tests/cheats/run.sh            every cheat
#   tests/cheats/run.sh <name>…    only these
#
# Each cheat is a directory: `kind` (pure or app: which frozen base app it starts from),
# `apply.sh` (run in a copy of that app; $NAME, $ROOT and $MIL are set) and `expect` (an
# extended regex the failing audit's output must match). The base apps are first checked to pass
# the strict audit, so a cheat's failure is the cheat's doing. A newly found bypass is added here
# first, then fixed.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
export ROOT MIL="$ROOT/cli/.lake/build/bin/mil"
W="$ROOT/bench/zcheats"   # inside the checkout (framework by relative path); removed on exit
trap 'rm -rf "$W"' EXIT
rm -rf "$W"; mkdir -p "$W"
names=("$@"); [ ${#names[@]} -gt 0 ] || names=($(cd "$ROOT/tests/cheats" && ls -d */ | tr -d /))

base() {  # <kind>: build, judge, freeze and strictly audit a fresh base app, once
  local kind=$1 dir="$W/base-$1" name flag=
  [ -d "$dir" ] && return
  if [ "$kind" = pure ]; then name=Zcheatpure; flag=--pure; else name=Zcheatapp; fi
  (cd "$ROOT" && "$MIL" init $flag "$name" "bench/zcheats/base-$kind" >/dev/null)
  "$MIL" judge "$dir/mil.json" >"$W/base-$kind.log" 2>&1 && "$MIL" freeze "$dir/mil.json" cheat-suite >>"$W/base-$kind.log" 2>&1 \
    && "$MIL" audit "$dir/mil.json" >>"$W/base-$kind.log" 2>&1 \
    || { echo "FAILED: the honest $kind base app does not pass the audit"; tail -30 "$W/base-$kind.log"; exit 1; }
  echo "control: honest $kind app, AUDIT PASSED"
}

fail=0
for c in "${names[@]}"; do
  d="$ROOT/tests/cheats/$c"; kind=$(cat "$d/kind"); base "$kind"
  app="$W/$c"; cp -a "$W/base-$kind" "$app"
  if [ "$kind" = pure ]; then export NAME=Zcheatpure; else export NAME=Zcheatapp; fi
  if ! (cd "$app" && "$d/apply.sh") >"$W/$c.apply.log" 2>&1; then
    echo "FAILED: $c: apply.sh failed"; tail -20 "$W/$c.apply.log"; fail=1; continue
  fi
  if "$MIL" audit "$app/mil.json" >"$W/$c.log" 2>&1; then
    echo "FAILED: $c: AUDIT PASSED (a bypass)"; fail=1
  elif grep -qE "$(cat "$d/expect")" "$W/$c.log"; then
    echo "cheat rejected: $c"
  else
    echo "FAILED: $c: rejected, but not for the expected reason ($(cat "$d/expect"))"; tail -15 "$W/$c.log"; fail=1
  fi
  rm -rf "$app"
done
[ $fail -eq 0 ] && echo "cheats: ${#names[@]}/${#names[@]} rejected" || exit 1
