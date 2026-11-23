#!/usr/bin/env python3
"""Check what the difftest generator reaches (http/REQUIREMENTS.md §7).

Generates the same sequences as `tools/difftest.py --seed S --runs R --length L`, answers them
with `ledger-oracle` (the frozen model), and requires that together they reach every command
with every answer it can give, every error code, `ERR USAGE`, and every limit.

Usage: tests/gen_coverage.py [runs] [length] [seed]   (from examples/ledger/impl)
"""
import importlib.util, os, random, subprocess, sys

HERE = os.path.dirname(os.path.abspath(__file__))
ORACLE = os.path.join(HERE, "..", ".lake", "build", "bin", "ledger-oracle")

spec = importlib.util.spec_from_file_location("gen_commands", os.path.join(HERE, "gen_commands.py"))
g = importlib.util.module_from_spec(spec); spec.loader.exec_module(g)

REQUIRED = {
    # every command with each answer it can give (§3)
    "cmd:open:OK", "cmd:open:ERR", "cmd:deposit:BALANCE", "cmd:deposit:ERR",
    "cmd:withdraw:BALANCE", "cmd:withdraw:ERR", "cmd:transfer:OK", "cmd:transfer:ERR",
    "cmd:balance:BALANCE", "cmd:balance:ERR", "cmd:accounts:ACCOUNTS", "cmd:total:TOTAL",
    # every error code
    "ERR BAD_NAME", "ERR BAD_AMOUNT", "ERR ACCOUNT_EXISTS", "ERR UNKNOWN_ACCOUNT",
    "ERR INSUFFICIENT_FUNDS", "ERR BALANCE_LIMIT", "ERR SAME_ACCOUNT", "ERR USAGE",
    # limits
    "amount 0", "amount 1", f"amount {g.MAX}", f"amount {g.MAX + 1}",
    "name 1", "name 64", "name 65", "balance at MAX", "total above MAX",
}


def main():
    runs = int(sys.argv[1]) if len(sys.argv) > 1 else 30
    length = int(sys.argv[2]) if len(sys.argv) > 2 else 200
    seed = int(sys.argv[3]) if len(sys.argv) > 3 else 1
    seen = set()
    for r in range(runs):
        lines = g.gen(random.Random(seed * 1_000_003 + r), length)
        out = subprocess.run([ORACLE], input="".join(l + "\n" for l in lines),
                             capture_output=True, text=True, check=True).stdout.splitlines()
        assert len(out) == len(lines), (len(out), len(lines))
        seen |= g.coverage(lines, out)
    missing = sorted(REQUIRED - seen)
    if missing:
        print(f"gen_coverage: FAIL, not reached: {missing}")
        sys.exit(1)
    print(f"gen_coverage: {runs} runs x {length} commands reach all {len(REQUIRED)} required cases")


if __name__ == "__main__":
    main()
