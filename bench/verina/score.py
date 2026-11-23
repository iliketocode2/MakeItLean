#!/usr/bin/env python3
"""Score a solution to a VERINA task against the task's tests (Phase 4, experiment A).

VERINA's rule, rebuilt with `decide` (no Plausible, by decision of 2026-11-23):
- code correct:    `f args h = expected`            for every test
- post sound:      `post args expected h` holds      for every test
- post complete:   `post args u h` fails             for every listed unexpected output u
- pre sound:       `pre args` holds                  for every test input
- pre complete:    `pre r` fails                     for every reject input r
A check whose proposition `decide` cannot evaluate (no Decidable instance, or it does not reduce)
is **unsettled**: reported, never counted as a pass or a failure.

usage: score.py TASK_DIR [--imports M1,M2 | --prelude FILE] --pre NAME --post NAME --code NAME --cwd LAKE_DIR [--json OUT]
  TASK_DIR  a VERINA task directory (task.json, test.json, reject_inputs.json), read as data
  --cwd     the Lake package whose environment can import the modules (run with `lake env lean`);
            omit to run plain `lean` (v4.36.0) on a file that imports nothing outside core
"""
import argparse, json, os, re, subprocess, sys, tempfile

LEAN = ["elan", "run", "leanprover/lean4:v4.36.0", "lean"]


def split_type(t):
    """Top-level split of a type application or tuple, respecting parentheses."""
    t = t.strip()
    while t.startswith("(") and t.endswith(")") and balanced(t[1:-1]):
        t = t[1:-1].strip()
    return t


def balanced(s):
    d = 0
    for ch in s:
        d += ch == "("
        d -= ch == ")"
        if d < 0:
            return False
    return d == 0


def top_split(s, sep):
    parts, d, cur = [], 0, ""
    i = 0
    while i < len(s):
        ch = s[i]
        d += ch == "("
        d -= ch == ")"
        if d == 0 and s.startswith(sep, i):
            parts.append(cur); cur = ""; i += len(sep); continue
        cur += ch; i += 1
    parts.append(cur)
    return [p.strip() for p in parts]


class Unsupported(Exception):
    pass


SAFE_TERM = re.compile(r"^[0-9A-Za-z_ ,.()\[\]#'\-+]*$")
FORBIDDEN = re.compile(r"\b(IO|eval|run_cmd|run_tac|unsafe|import|open|macro|syntax|elab|by)\b")


def lean_text(v, ty):
    """A value VERINA stores as Lean source text (`"some 2"`, `"#[1, 2]"`, `"(1, [2])"`), ascribed to
    its type. The text is untrusted data pasted into a file Lean evaluates, so only plain literal
    syntax is accepted: digits, names, brackets, commas, `#`, `-`, `'`; no command words."""
    if not SAFE_TERM.match(v) or FORBIDDEN.search(v):
        raise Unsupported(f"value text not accepted: {v[:40]!r}")
    return f"({v} : {ty})"


def lit(v, ty):
    """A Lean term of type `ty` for the JSON value `v`."""
    ty = split_type(ty)
    if isinstance(v, str) and ty not in ("String", "Char"):
        return lean_text(v, ty)
    prod = top_split(ty, "×")
    if len(prod) > 1:
        return "(" + ", ".join(lit(x, t) for x, t in zip(v, prod)) + ")"
    if ty.startswith("Prod "):
        args = top_split(ty[5:], " ")
        if len(args) != 2:
            raise Unsupported(ty)
        return f"({lit(v[0], args[0])}, {lit(v[1], args[1])})"
    head, _, arg = ty.partition(" ")
    if ty in ("Int", "Nat"):
        n = int(v)
        return f"({n} : {ty})" if n >= 0 else f"(({n}) : {ty})"
    if ty == "Bool":
        return "true" if v else "false"
    if ty == "String":
        return json.dumps(v, ensure_ascii=False)
    if ty == "Char":
        if not isinstance(v, str) or len(v) != 1:
            raise Unsupported(f"Char {v!r}")
        return "'" + ("\\'" if v == "'" else "\\\\" if v == "\\" else v) + "'"
    if ty == "UInt8":
        return f"({int(v)} : UInt8)"
    if head in ("List", "Array"):
        items = ", ".join(lit(x, arg) for x in v)
        return f"([{items}] : List {split_type(arg)})" if head == "List" else f"(#[{items}] : Array {split_type(arg)})"
    if head == "Option":
        return f"(none : Option {split_type(arg)})" if v is None else f"(some {lit(v, arg)})"
    raise Unsupported(ty)


def parse_value(v):
    """VERINA stores some values as strings of Lean/JSON text; decode when that is the case."""
    if isinstance(v, str):
        try:
            return json.loads(v)
        except Exception:
            return v
    return v


def build(task_dir, a):
    task = json.load(open(os.path.join(task_dir, "task.json")))
    sig = task["signature"]
    params, ret = sig["parameters"], sig["return_type"]
    tests = json.load(open(os.path.join(task_dir, "test.json")))
    rejects_path = os.path.join(task_dir, "reject_inputs.json")
    rejects = json.load(open(rejects_path)) if os.path.exists(rejects_path) else []
    checks = []  # (kind, lean expression of type Bool)

    def args_of(inp):
        return " ".join(lit(parse_value(inp[p["param_name"]]), p["param_type"]) for p in params)

    for i, t in enumerate(tests):
        try:
            args = args_of(t["input"])
            exp = lit(parse_value(t["expected"]), ret)
            h = f"(by decide : {a.pre} {args})" if params else f"(by decide : {a.pre})"
            checks.append((f"pre_sound#{i}", f"decide ({a.pre} {args})"))
            checks.append((f"code#{i}", f"decide ({a.code} {args} {h} = {exp})"))
            checks.append((f"post_sound#{i}", f"decide ({a.post} {args} {exp} {h})"))
            for j, u in enumerate(t.get("unexpected", [])):
                checks.append((f"post_complete#{i}.{j}", f"!decide ({a.post} {args} {lit(parse_value(u), ret)} {h})"))
        except Unsupported as e:
            checks.append((f"unsupported#{i}", f"/* {e} */"))
    for i, r in enumerate(rejects):
        try:
            checks.append((f"pre_complete#{i}", f"!decide ({a.pre} {args_of(r['input'])})"))
        except (Unsupported, KeyError) as e:
            checks.append((f"unsupported#r{i}", f"/* {e} */"))
    return checks


def run(checks, a):
    head = "".join(f"import {m}\n" for m in a.imports.split(",") if m) + "\n"
    if a.prelude:  # a whole solution file pasted in front (for scoring VERINA's reference files)
        pre = open(a.prelude).read()
        imports = [l for l in pre.splitlines() if l.startswith("import ")]
        rest = "\n".join(l for l in pre.splitlines() if not l.startswith("import "))
        head = "\n".join(imports) + "\n" + head + rest + "\n\n"
    lines, where = [], {}
    for k, (name, expr) in enumerate(checks):
        if name.startswith("unsupported"):
            continue
        lines.append(f'#eval IO.println s!"CHECK {k} {{{expr}}}"')
    body = head + "\n".join(lines) + "\n"
    first = head.count("\n") + 1
    with tempfile.NamedTemporaryFile("w", suffix=".lean", delete=False, dir=a.cwd or None) as f:
        f.write(body)
        path = f.name
    try:
        cmd = (["lake", "env", "lean", path] if a.cwd else LEAN + [path])
        r = subprocess.run(cmd, capture_output=True, text=True, cwd=a.cwd or None, timeout=900)
    finally:
        os.unlink(path)
    out = r.stdout + r.stderr
    got = {int(m.group(1)): m.group(2) == "true" for m in re.finditer(r"^CHECK (\d+) (true|false)$", out, re.M)}
    errline = {int(m.group(1)) for m in re.finditer(r":(\d+):\d+: error", out)}
    results = {}
    li = 0
    for k, (name, expr) in enumerate(checks):
        if name.startswith("unsupported"):
            results[name] = "unsupported"
            continue
        lineno = first + li
        li += 1
        results[name] = "pass" if got.get(k) is True else "fail" if k in got else "unsettled"
        if lineno in errline and k not in got:
            results[name] = "unsettled"
    return results


def summary(results):
    s = {}
    for name, v in results.items():
        kind = name.split("#")[0]
        s.setdefault(kind, {"pass": 0, "fail": 0, "unsettled": 0, "unsupported": 0})[v] += 1
    return s


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("task_dir")
    ap.add_argument("--imports", default="")
    ap.add_argument("--pre", required=True)
    ap.add_argument("--post", required=True)
    ap.add_argument("--code", required=True)
    ap.add_argument("--cwd", default="")
    ap.add_argument("--prelude", default="", help="a solution file to paste before the checks")
    ap.add_argument("--json", default="")
    a = ap.parse_args()
    results = run(build(a.task_dir, a), a)
    s = summary(results)
    if a.json:
        json.dump({"checks": results, "summary": s}, open(a.json, "w"), indent=1)
    print(json.dumps(s))


if __name__ == "__main__":
    main()
