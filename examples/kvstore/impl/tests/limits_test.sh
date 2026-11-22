#!/usr/bin/env bash
# Stage 7 regression: inputs at the R1/R8a limits must work end to end (they used to overflow the
# stack). A 10,000-write batch of ~60 MB through `serve`, then reopen, read back, and check.
set -euo pipefail
K="$(dirname "$0")/../.lake/build/bin/leankv"
D="${1:-/tmp/leankv-limits}"; rm -rf "$D"
out=$(python3 -I -c "
v='c'*6000
print('batch ' + ' '.join(f'put k{i} {v}' for i in range(10000)))
print('put big ' + 'x'*(1024*1024))
print('get k9999')" | "$K" "$D" serve | cut -c1-12 | tr '\n' ' ')
[ "$out" = "OK OK VALUE cccccc " ] || { echo "FAIL: $out"; exit 1; }
v=$("$K" "$D" get big | cut -c1-12)
[ "$v" = "VALUE xxxxxx" ] || { echo "FAIL: reopen ($v)"; exit 1; }
"$K" "$D" check | grep -q 'records=2 ' || { echo "FAIL: check"; exit 1; }
n=$("$K" "$D" scan '""' '\inf' 100000 | cut -d' ' -f2)
[ "$n" = "10001" ] || { echo "FAIL: scan $n"; exit 1; }
rm -rf "$D"; echo "limits test: 60 MB batch + 1 MiB value OK (serve, reopen, scan, check)"
