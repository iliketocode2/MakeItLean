#!/usr/bin/env python3
"""Score one A2 batch (run from the main session: it reads the hidden tests).

For each task in runs/a2/batchN.json:
- framework: `mil check-lock` and `mil judge` (proof accepted by the comparator), then score.py
- baseline: the file builds, its theorem uses only the standard axioms (so no sorry, no
  native_decide, no custom axiom), then score.py
Writes runs/a2/batchN_scores.json and prints a table.

usage: batch_score.py N
"""
import json, os, re, subprocess, sys, tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.realpath(os.path.join(HERE, "..", ".."))
MIL = os.path.join(ROOT, "cli", ".lake", "build", "bin", "mil")
DATA = os.path.expanduser("~/bench/verina/datasets/verina")
STD = {"propext", "Classical.choice", "Quot.sound"}


def run(cmd, cwd=None, timeout=1800):
    r = subprocess.run(cmd, cwd=cwd, capture_output=True, text=True, timeout=timeout)
    return r.returncode, r.stdout + r.stderr


def score(task, s):
    cmd = [sys.executable, "-I", os.path.join(HERE, "score.py"), os.path.join(DATA, task),
           "--pre", s["pre"], "--post", s["post"], "--code", s["code"]]
    if "prelude" in s:
        cmd += ["--prelude", s["prelude"]]
    else:
        cmd += ["--imports", s["imports"], "--cwd", s["cwd"]]
    code, out = run(cmd)
    try:
        return json.loads(out.strip().splitlines()[-1])
    except Exception:
        return {"error": out[-400:]}


def framework_proof(fdir):
    c1, o1 = run([MIL, "check-lock", "mil.json"], cwd=fdir)
    c2, o2 = run([MIL, "judge", "mil.json"], cwd=fdir)
    return {"lock_ok": c1 == 0, "accepted": c2 == 0 and "ACCEPTED" in o2}


def baseline_proof(bdir, fn):
    src = open(os.path.join(bdir, "Solution.lean")).read()
    with tempfile.NamedTemporaryFile("w", suffix=".lean", delete=False) as f:
        f.write(src + f"\n#print axioms {fn}_spec_satisfied\n")
        p = f.name
    try:
        code, out = run(["elan", "run", "leanprover/lean4:v4.36.0", "lean", p])
    finally:
        os.unlink(p)
    m = re.search(r"depends on axioms: \[([^\]]*)\]", out)
    axioms = {a.strip() for a in m.group(1).split(",")} if m else set()
    if "does not depend on any axioms" in out:
        axioms, m = set(), True
    return {"builds": code == 0, "axioms": sorted(axioms), "accepted": code == 0 and bool(m) and axioms <= STD}


def flat(s):
    """pass/total per check kind, and whether every settled check passed."""
    out = {}
    for k, c in s.items():
        if isinstance(c, dict) and "pass" in c:
            out[k] = f"{c['pass']}/{c['pass'] + c['fail']}" + (f" ({c['unsettled']} unsettled)" if c["unsettled"] else "")
    return out


def main():
    n = sys.argv[1]
    batch = json.load(open(os.path.join(ROOT, "bench", "verina", "runs", "a2", f"batch{n}.json")))
    res = []
    for t in batch["tasks"]:
        fp = framework_proof(t["fdir"])
        bp = baseline_proof(t["bdir"], t["fn"])
        fs, bs = score(t["task"], t["fscore"]), score(t["task"], t["bscore"])
        res.append({"task": t["task"], "framework": {**fp, "score": fs}, "baseline": {**bp, "score": bs}})
        print(f"{t['task']:20} framework: lock={'ok' if fp['lock_ok'] else 'CHANGED'} proof={'ACCEPTED' if fp['accepted'] else 'no'} {flat(fs)}")
        print(f"{'':20} baseline:  builds={bp['builds']} proof={'ok' if bp['accepted'] else 'no ' + str(bp['axioms'])} {flat(bs)}")
    json.dump(res, open(os.path.join(ROOT, "bench", "verina", "runs", "a2", f"batch{n}_scores.json"), "w"), indent=1)


if __name__ == "__main__":
    main()
