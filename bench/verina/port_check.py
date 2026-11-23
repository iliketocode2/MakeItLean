"""Phase 4 A0 feasibility check: does each VERINA task's reference spec (and full reference solution) elaborate
on Lean 4.36 without Mathlib? Reads ~/bench/verina (untrusted data, text only), writes generated
Lean files into OUT, runs `lean` (v4.36.0) on each, and writes a JSON summary.

usage: python3 -I port_check.py <verina_datasets_dir> <out_dir>
"""
import json, os, re, subprocess, sys
from concurrent.futures import ThreadPoolExecutor

SRC, OUT = sys.argv[1], sys.argv[2]
LEAN = ["elan", "run", "leanprover/lean4:v4.36.0", "lean"]
SEC = re.compile(r"-- !benchmark @start (\S+)(?: [^\n]*)?\n(.*?)-- !benchmark @end \1", re.S)


def sections(text):
    return {m.group(1): m.group(2) for m in SEC.finditer(text)}


def strip_markers(text, replace=None):
    """The task file with marker lines removed; `replace` maps a section name to new content."""
    replace = replace or {}
    def sub(m):
        name, body = m.group(1), m.group(2)
        return replace.get(name, body)
    return SEC.sub(sub, text)


def variants(text):
    imports = sections(text).get("import", "")
    kept = "\n".join(l for l in imports.splitlines() if l.startswith("import") and "Mathlib" not in l)
    # spec only: the reference preconditions/postconditions; code is `sorry`, proof is `sorry`
    spec = strip_markers(text, {"import": kept + "\n", "code": "  sorry\n", "proof": "  sorry\n",
                                "proof_aux": ""})
    full = strip_markers(text, {"import": kept + "\n"})
    return spec, full


def check(path):
    r = subprocess.run(LEAN + [path], capture_output=True, text=True, timeout=300)
    errs = [l for l in (r.stdout + r.stderr).splitlines() if ": error" in l]
    return r.returncode == 0, errs[:3]


def one(task):
    text = open(os.path.join(SRC, task, "task.lean")).read()
    uses_mathlib = "Mathlib" in sections(text).get("import", "")
    spec, full = variants(text)
    res = {"task": task, "ref_imports_mathlib": uses_mathlib}
    for kind, src in (("spec", spec), ("full", full)):
        p = os.path.join(OUT, f"{task}_{kind}.lean")
        open(p, "w").write(src)
        ok, errs = check(p)
        res[kind] = ok
        res[kind + "_errors"] = errs
    return res


tasks = sorted(t for t in os.listdir(SRC) if os.path.isfile(os.path.join(SRC, t, "task.lean")))
os.makedirs(OUT, exist_ok=True)
with ThreadPoolExecutor(max_workers=6) as ex:
    results = list(ex.map(one, tasks))
json.dump(results, open(os.path.join(OUT, "summary.json"), "w"), indent=1)
n = len(results)
for split in ("basic", "advanced"):
    rs = [r for r in results if f"_{split}_" in r["task"]]
    print(f"{split:8} {len(rs):3} tasks: spec builds without Mathlib {sum(r['spec'] for r in rs):3}, "
          f"full reference builds {sum(r['full'] for r in rs):3}, reference imports Mathlib {sum(r['ref_imports_mathlib'] for r in rs):3}")
print(f"all      {n:3} tasks: spec {sum(r['spec'] for r in results)}, full {sum(r['full'] for r in results)}")
