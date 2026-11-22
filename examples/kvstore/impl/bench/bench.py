#!/usr/bin/env python3
"""R19 benchmark: LeanKV vs SQLite on the same machine (Stage 7).

LeanKV runs as `leankv serve` driven over a pipe (each op pays a process round trip and the
text protocol). SQLite runs in-process from Python (WAL, synchronous=FULL, one transaction per
durable write) - this setup favours SQLite. Every acknowledged write is fsynced in both.
Reports ops/s and p50/p99 latency per workload.
"""
import os, random, shutil, sqlite3, subprocess, sys, time

LEANKV = os.path.join(os.path.dirname(__file__), "..", ".lake", "build", "bin", "leankv")

def key(i): return b"user%012d" % i
def val(i, n=100): return (b"%08d" % i) * (n // 8)

def esc(b):
    return "".join(chr(x) if 0x21 <= x <= 0x7E and x not in (0x5C, 0x22) else "\\x%02x" % x for x in b) or '""'

def pct(xs, p):
    xs = sorted(xs); return xs[min(len(xs) - 1, int(p * len(xs)))]

def fmt(name, lat, wall):
    n = len(lat)
    return f"  {name:<28} {n/wall:>10,.0f} ops/s   p50 {pct(lat,.5)*1e6:>8,.0f} µs   p99 {pct(lat,.99)*1e6:>8,.0f} µs"

class LeanKV:
    def __init__(self, d):
        shutil.rmtree(d, ignore_errors=True); self.d = d; self.start()
    def start(self):
        self.p = subprocess.Popen([LEANKV, self.d, "serve"], stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True, bufsize=1)
    def req(self, line):
        self.p.stdin.write(line + "\n"); self.p.stdin.flush(); return self.p.stdout.readline()
    # request lines are built before timing (see `prep`), so only the store's round trip is timed
    def prep_put(self, k, v): return f"put {esc(k)} {esc(v)}"
    def prep_get(self, k): return f"get {esc(k)}"
    def prep_scan(self, lo, n): return f"scan {esc(lo)} \\inf {n}"
    def prep_batch(self, kvs): return "batch " + " ".join(f"put {esc(k)} {esc(v)}" for k, v in kvs)
    def put(self, line): assert self.req(line).startswith("OK")
    def get(self, line): return self.req(line)
    def scan(self, line): return self.req(line)
    def batch(self, line): assert self.req(line).startswith("OK")
    def close(self): self.p.stdin.close(); self.p.wait()
    def reopen(self):
        self.close(); t = time.perf_counter(); self.start(); self.get(self.prep_get(b"x")); return time.perf_counter() - t

class SQLite:
    def __init__(self, d):
        shutil.rmtree(d, ignore_errors=True); os.makedirs(d); self.path = os.path.join(d, "db.sqlite"); self.start()
        self.c.execute("CREATE TABLE kv(k BLOB PRIMARY KEY, v BLOB) WITHOUT ROWID")
    def start(self):
        self.c = sqlite3.connect(self.path, isolation_level=None)
        self.c.execute("PRAGMA journal_mode=WAL"); self.c.execute("PRAGMA synchronous=FULL")
    def prep_put(self, k, v): return (k, v)
    def prep_get(self, k): return k
    def prep_scan(self, lo, n): return (lo, n)
    def prep_batch(self, kvs): return kvs
    def put(self, kv):
        k, v = kv
        self.c.execute("BEGIN"); self.c.execute("INSERT OR REPLACE INTO kv VALUES(?,?)", (k, v)); self.c.execute("COMMIT")
    def get(self, k): return self.c.execute("SELECT v FROM kv WHERE k=?", (k,)).fetchone()
    def scan(self, a): return self.c.execute("SELECT k,v FROM kv WHERE k>=? ORDER BY k LIMIT ?", a).fetchall()
    def batch(self, kvs):
        self.c.execute("BEGIN"); self.c.executemany("INSERT OR REPLACE INTO kv VALUES(?,?)", kvs); self.c.execute("COMMIT")
    def close(self): self.c.close()
    def reopen(self):
        self.close(); t = time.perf_counter(); self.start(); self.get(self.prep_get(b"x")); return time.perf_counter() - t

def timed(fn, items):
    lat = []; t0 = time.perf_counter()
    for it in items:
        t = time.perf_counter(); fn(it); lat.append(time.perf_counter() - t)
    return lat, time.perf_counter() - t0

def run(store, n_put, n_load, n_get, n_scan, n_batch):
    rng = random.Random(1)
    out = []
    puts = [store.prep_put(key(i), val(i)) for i in range(n_put)]
    lat, w = timed(store.put, puts); out.append(fmt("put (durable, 100 B)", lat, w))
    loads = [store.prep_batch([(key(i), val(i)) for i in range(b, b + 100)]) for b in range(n_put, n_put + n_load, 100)]
    t0 = time.perf_counter()
    for l in loads: store.batch(l)
    load_s = time.perf_counter() - t0
    out.append(f"  {'bulk load (batches of 100)':<28} {n_load/load_s:>10,.0f} keys/s")
    total = n_put + n_load
    gets = [store.prep_get(key(rng.randrange(total))) for _ in range(n_get)]
    lat, w = timed(store.get, gets); out.append(fmt("get (random)", lat, w))
    scans = [store.prep_scan(key(rng.randrange(total)), 10) for _ in range(n_scan)]
    lat, w = timed(store.scan, scans); out.append(fmt("scan (10 pairs)", lat, w))
    batches = [store.prep_batch([(key(rng.randrange(total)), val(b)) for _ in range(100)]) for b in range(n_batch)]
    lat, w = timed(store.batch, batches)
    out.append(fmt("batch of 100 puts (durable)", lat, w) + f"   = {100*n_batch/w:,.0f} writes/s")
    out.append(f"  {'reopen (' + str(total) + ' keys)':<28} {store.reopen()*1000:>10,.1f} ms")
    store.close()
    return out

if __name__ == "__main__":
    base = sys.argv[1] if len(sys.argv) > 1 else "/tmp/leankv-bench"
    sizes = dict(n_put=1000, n_load=50000, n_get=20000, n_scan=5000, n_batch=200)
    for name, cls in [("LeanKV (serve, over a pipe)", LeanKV), ("SQLite 3.45 (in-process, WAL, synchronous=FULL)", SQLite)]:
        print(name)
        for line in run(cls(os.path.join(base, cls.__name__)), **sizes): print(line)
