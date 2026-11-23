"""Command generator for difftest: every command, the usage error and the name-length limits.
(The counter limit 2^64 - 1 is out of reach by increments; it is a `#guard` in the spec.)"""

NAMES = ["a", "b", "c", "x" * 64]
BAD_NAMES = ["x" * 65]


def gen(rng, n):
    out = []
    for _ in range(n):
        r = rng.random()
        if r < 0.55:
            out.append(f"incr {rng.choice(NAMES)}")
        elif r < 0.85:
            out.append(f"get {rng.choice(NAMES)}")
        elif r < 0.93:
            out.append(f"{rng.choice(['incr', 'get'])} {rng.choice(BAD_NAMES)}")
        else:
            out.append(rng.choice(["bogus", "incr", "get a b", ""]))
    return out
