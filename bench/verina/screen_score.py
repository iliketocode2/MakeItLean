#!/usr/bin/env python3
"""Score the A2 screen (baseline only) from the main session; prints failures and a summary.

usage: screen_score.py [TASK ...]   (default: every task in runs/screen/screen.json whose
Solution.lean no longer contains a sorry in code)
Writes runs/screen/screen_scores.json (merged with earlier results).
"""
import json, os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from batch_score import baseline_proof, score, flat  # noqa: E402

ROOT = os.path.realpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
S = os.path.join(ROOT, "bench", "verina", "runs", "screen")
tasks = json.load(open(os.path.join(S, "screen.json")))["tasks"]
want = set(sys.argv[1:])
path = os.path.join(S, "screen_scores.json")
results = json.load(open(path)) if os.path.exists(path) else {}
for t in tasks:
    if want and t["task"] not in want:
        continue
    p = baseline_proof(t["bdir"], t["fn"])
    s = score(t["task"], t["bscore"])
    ok_checks = all(c["fail"] == 0 for k, c in s.items() if isinstance(c, dict) and "fail" in c)
    fail = not (p["accepted"] and ok_checks) or "error" in s
    results[t["task"]] = {"proof": p, "score": s, "baseline_failure": fail}
    print(f"{t['task']:20} {'FAIL' if fail else 'ok  '} proof={'ok' if p['accepted'] else 'no ' + str(p['axioms'])} {flat(s) if 'error' not in s else s}")
json.dump(results, open(path, "w"), indent=1)
n = len(results); f = sum(r["baseline_failure"] for r in results.values())
print(f"scored so far: {n}; baseline failures: {f}")
