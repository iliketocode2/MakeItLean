#!/usr/bin/env python3
"""R10/R11 kill tests on the real file system (Stage 5).

Start `leankv <dir> serve`, send random writes, SIGKILL it at a random moment (sometimes right
after sending a write whose reply is never read), then reopen and compare the whole store with
the writes that were acknowledged. Allowed: exactly the acknowledged writes, or those plus the
one write in flight, applied in full. The random seed of every run is printed, so failures replay.

Note: SIGKILL loses nothing that reached the kernel. Power loss (data written but not fsynced) is
covered by the model-level proofs and the R23 harness, not here.
"""
import os, random, shutil, signal, subprocess, sys, time

LEANKV = os.path.join(os.path.dirname(__file__), "..", ".lake", "build", "bin", "leankv")

def unescape(tok: str) -> bytes:
    if tok == '""': return b""
    out, i = bytearray(), 0
    while i < len(tok):
        c = tok[i]
        if c == "\\":
            n = tok[i + 1]
            if n == "\\": out.append(0x5C); i += 2
            elif n == "n": out.append(0x0A); i += 2
            elif n == "t": out.append(0x09); i += 2
            elif n == "x": out.append(int(tok[i + 2:i + 4], 16)); i += 4
            else: raise ValueError(tok)
        else: out.append(ord(c)); i += 1
    return bytes(out)

def escape(b: bytes) -> str:
    if not b: return '""'
    s = []
    for x in b:
        if 0x21 <= x <= 0x7E and x not in (0x5C, 0x22): s.append(chr(x))
        elif x == 0x5C: s.append("\\\\")
        elif x == 0x0A: s.append("\\n")
        elif x == 0x09: s.append("\\t")
        else: s.append("\\x%02x" % x)
    return "".join(s)

def scan_all(d):
    r = subprocess.run([LEANKV, d, "scan", '""', "\\inf", "100000000"], capture_output=True, text=True)
    assert r.returncode == 0, (r.returncode, r.stdout)
    toks = r.stdout.split()
    assert toks[0] == "PAIRS"
    pairs = toks[2:]
    return {unescape(pairs[i]): unescape(pairs[i + 1]) for i in range(0, len(pairs), 2)}

def apply(model, op):
    model = dict(model)
    for kind, k, v in op:
        if kind == "put": model[k] = v
        else: model.pop(k, None)
    return model

def rand_op(rng):
    def key(): return bytes([rng.choice(b"abcdefgh"), rng.choice([0x41, 0xC7, 0x00, 0x7A])])
    def val(): return bytes(rng.randrange(256) for _ in range(rng.choice([0, 1, 5, 50, 3000])))
    n = rng.choice([1, 1, 1, 3])
    return [("put", key(), val()) if rng.random() < 0.7 else ("delete", key(), None) for _ in range(n)]

def line_of(op):
    if len(op) == 1:
        kind, k, v = op[0]
        return f"put {escape(k)} {escape(v)}" if kind == "put" else f"delete {escape(k)}"
    parts = ["batch"]
    for kind, k, v in op:
        parts += ["put", escape(k), escape(v)] if kind == "put" else ["delete", escape(k)]
    return " ".join(parts)

def one_run(seed, base):
    rng = random.Random(seed)
    d = os.path.join(base, f"kill-{seed}")
    shutil.rmtree(d, ignore_errors=True)
    model = {}
    for life in range(rng.randrange(2, 5)):
        p = subprocess.Popen([LEANKV, d, "serve"], stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True, bufsize=1)
        inflight = None
        for _ in range(rng.randrange(1, 40)):
            op = rand_op(rng)
            p.stdin.write(line_of(op) + "\n"); p.stdin.flush()
            if rng.random() < 0.15:          # kill with this write in flight
                inflight = op
                if rng.random() < 0.5: time.sleep(rng.random() * 0.003)
                break
            resp = p.stdout.readline().strip()
            if resp != "OK": raise AssertionError(f"seed {seed}: unexpected reply {resp!r}")
            model = apply(model, op)
        p.send_signal(signal.SIGKILL); p.wait()
        got = scan_all(d)
        allowed = [model] + ([apply(model, inflight)] if inflight else [])
        if got not in allowed:
            raise AssertionError(f"seed {seed} life {life}: store has {len(got)} keys, not an allowed state")
        model = got
        chk = subprocess.run([LEANKV, d, "check"], capture_output=True, text=True)
        if chk.returncode != 0: raise AssertionError(f"seed {seed}: check failed: {chk.stdout}")
    shutil.rmtree(d, ignore_errors=True)

if __name__ == "__main__":
    base = sys.argv[1] if len(sys.argv) > 1 else "/tmp/leankv-kill"
    n = int(sys.argv[2]) if len(sys.argv) > 2 else 40
    os.makedirs(base, exist_ok=True)
    fails = 0
    for seed in range(n):
        try: one_run(seed, base)
        except AssertionError as e: print("FAIL", e); fails += 1
    print(f"kill tests: {n - fails}/{n} runs consistent (seeds 0..{n-1})")
    sys.exit(1 if fails else 0)
