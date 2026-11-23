"""(Phase 4 A1; run from the scratch directory holding port_check.py output in ./out) Run score.py on every VERINA reference solution that builds on 4.36: the scorer must find the
reference code correct and the reference spec sound and complete wherever `decide` settles it."""
import json, os, subprocess, sys
from concurrent.futures import ThreadPoolExecutor
D = os.path.expanduser("~/bench/verina/datasets/verina")
OUT = os.path.dirname(os.path.abspath(__file__)) + "/out"
SC = os.path.expanduser("~/MakeItLean/bench/verina/score.py")
summ = json.load(open(OUT + "/summary.json"))
def one(r):
    t = r["task"]
    if not (r["full"] or r["spec"]):
        return t, None
    kind = "full" if r["full"] else "spec"   # spec-only files: code is `sorry`, only spec checks count
    name = json.load(open(f"{D}/{t}/task.json"))["signature"]["name"]
    p = subprocess.run([sys.executable, "-I", SC, f"{D}/{t}", "--prelude", f"{OUT}/{t}_{kind}.lean",
                        "--pre", f"{name}_precond", "--post", f"{name}_postcond", "--code", name],
                       capture_output=True, text=True, timeout=1200)
    try:
        d = json.loads(p.stdout.strip().splitlines()[-1]); d['_kind'] = kind; return t, d
    except Exception:
        return t, {"error": (p.stdout + p.stderr)[-300:]}
with ThreadPoolExecutor(6) as ex:
    res = dict(ex.map(one, summ))
json.dump(res, open(OUT + "/validate.json", "w"), indent=1)
tot = {}
bad = []
for t, s in res.items():
    if s is None: continue
    if "error" in s: bad.append((t, "error")); continue
    for kind, c in s.items():
        if kind == '_kind': continue
        for k, v in c.items(): tot.setdefault(kind, {}).setdefault(k, 0); tot[kind][k] += v
        if c.get("fail") and not (s['_kind'] == 'spec' and kind == 'code'): bad.append((t, kind))
print("tasks scored:", sum(1 for s in res.values() if s is not None))
for kind, c in sorted(tot.items()): print(f"  {kind:14} {c}")
print("tasks with a FAIL or error (should be none if the scorer is right):", len(bad))
for b in bad[:15]: print("   ", b)
