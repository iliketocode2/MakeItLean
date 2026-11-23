"""Command generator for `tools/difftest.py` (http/REQUIREMENTS.md §7, V1, V2).

`gen(rng, n)` returns n protocol lines. Together the runs reach every command, every error code,
`ERR USAGE` (amounts `12.50`, `-5`, `1e3`, `+5`, wrong word counts, unknown words, empty lines)
and the limits: amounts 0, 1, MAX, MAX+1; names of 1, 64 and 65 bytes; a balance at MAX (a
fresh account receiving MAX); a total above MAX (two accounts holding large balances).
`coverage()` below checks this on the oracle's answers.
"""

MAX = 2**63 - 1
N64 = "x" * 64
N65 = "y" * 65
NAMES = ["a", "b", "c", "B", "A-b_c.9", N64]   # valid (R2); "B" < "a" bytewise
BIG = ["m1", "m2"]                             # accounts that receive MAX
BAD_NAMES = [N65, "bad/name", "é", "?", "a:b"]
AMOUNTS_SPECIAL = ["0", "1", str(MAX), str(MAX + 1), str(MAX - 1), str(2**64),
                   "99999999999999999999999", "007", "00"]
AMOUNTS_USAGE = ["12.50", "-5", "1e3", "+5", "0x10", "5a"]
USAGE_LINES = ["open", "open a b", "deposit a", "deposit a 1 2", "withdraw", "withdraw a",
               "transfer a b", "transfer a b c 1", "balance", "balance a b", "accounts x",
               "total 1", "bogus", "", "OPEN a", "Deposit a 5", "serve"]


def amount(rng):
    r = rng.random()
    if r < 0.8:
        return str(rng.randint(1, 1000))
    return rng.choice(AMOUNTS_SPECIAL)


def name(rng):
    return rng.choice(NAMES + BIG) if rng.random() < 0.15 else rng.choice(NAMES)


def gen(rng, n):
    out = []
    while len(out) < n:
        r = rng.random()
        if r < 0.12:
            out.append(f"open {name(rng)}")
        elif r < 0.30:
            out.append(f"deposit {name(rng)} {amount(rng)}")
        elif r < 0.42:
            out.append(f"withdraw {name(rng)} {amount(rng)}")
        elif r < 0.62:
            out.append(f"transfer {name(rng)} {name(rng)} {amount(rng)}")
        elif r < 0.70:
            out.append(f"balance {name(rng)}")
        elif r < 0.74:
            out.append("accounts")
        elif r < 0.78:
            out.append("total")
        elif r < 0.84:
            bad = rng.choice(BAD_NAMES)
            out.append(rng.choice([f"open {bad}", f"deposit {bad} 5", f"withdraw {bad} 5",
                                   f"balance {bad}", f"transfer {bad} a 5", f"transfer a {bad} 5",
                                   f"transfer {bad} {bad} 0"]))
        elif r < 0.89:
            bad = rng.choice(AMOUNTS_USAGE)
            out.append(rng.choice([f"deposit a {bad}", f"withdraw a {bad}",
                                   f"transfer a b {bad}", f"deposit {N65} {bad}"]))
        elif r < 0.94:
            out.append(rng.choice(USAGE_LINES))
        elif r < 0.97:
            # extra spaces between words (R18: one or more spaces)
            out.append(f"deposit  {name(rng)}   {amount(rng)} ")
        else:
            # a fresh account receiving MAX: a balance at MAX, then BALANCE_LIMIT and totals > MAX
            b = rng.choice(BIG)
            out += [f"open {b}", f"deposit {b} {MAX}"]
    return out[:n]


def coverage(lines, answers):
    """What a set of (line, oracle answer) pairs reached; used by tests/gen_coverage.py."""
    seen = set()
    for line, ans in zip(lines, answers):
        w = line.split()
        cmd = w[0] if w else ""
        seen.add(f"cmd:{cmd}:{ans.split()[0]}")
        if ans.startswith("ERR"):
            seen.add(" ".join(ans.split()[:2]))
        if ans == f"BALANCE {MAX}":
            seen.add("balance at MAX")
        if ans.startswith("TOTAL") and int(ans.split()[1]) > MAX:
            seen.add("total above MAX")
        for a in ("0", "1", str(MAX), str(MAX + 1)):
            if len(w) >= 3 and w[-1] == a:
                seen.add(f"amount {a}")
        for nm, tag in ((N64, "name 64"), (N65, "name 65"), ("a", "name 1")):
            if nm in w[1:]:
                seen.add(tag)
    return seen
