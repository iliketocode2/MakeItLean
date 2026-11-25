#!/usr/bin/env python3
"""Stage 5 self-test (`mil selftest`): the trusted shell against the frozen model, with mutants.

1. Build the CLI and the oracle. Copy the oracle binary aside: every later run uses this copy,
   built from the unmutated sources, as the reference.
2. Differential test: `<cli> {dir} serve` against the oracle on random command sequences
   (`tools/difftest.py`, the app's generator). It must agree on every answer. The app's own CLI
   test (`--test`, for the one-shot path `serve` does not reach) must pass too.
3. Mutation testing. `mil` chooses the mutants, not the app: fixed operators applied to the
   shell's source files (string and number literals, comparisons, boolean operators), at sites
   outside comments, evenly sampled up to a maximum. Each mutant that builds is run through the
   differential test, then the app's CLI test; it is killed if either fails. Because the oracle binary was copied before
   any mutation, a mutant in a parser or printer shared with the oracle is still caught.
   The score is killed / built, and must reach the minimum.
4. Restore every file (also on an interrupt), rebuild the CLI, write `.mil/selftest.json`.

    python3 -I tools/selftest.py --impl <impl dir> --cli-root <module> --oracle-root <module>
        --gen tests/gen_commands.py --file <shell source>… [--test tests/cli_test.sh]
        [--runs N] [--length N] [--min-score F] [--max-mutants N]

Exit 0 when the differential test passes and the score reaches the minimum; 1 otherwise; 2 on
usage errors.
"""
import argparse, json, os, re, shutil, signal, subprocess, sys, tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
DIFFTEST = os.path.join(HERE, "difftest.py")

# (name, regex, replacement function). Each match is one mutation site.
OPERATORS = [
    ("string", re.compile(r'"((?:[^"\\\n]|\\.)*)"'),
     lambda m: '"~' + m.group(1) + '"'),  # at the front: breaks whole-line and prefix checks alike
    ("eq", re.compile(r"(?<![=!<>])==(?!=)"), lambda m: "!="),
    ("neq", re.compile(r"!="), lambda m: "=="),
    ("and", re.compile(r"&&"), lambda m: "||"),
    ("or", re.compile(r"\|\|"), lambda m: "&&"),
    ("le", re.compile(r"(?<=\s)(<=|≤)(?=\s)"), lambda m: "<"),
    ("lt", re.compile(r"(?<=\s)<(?=\s)"), lambda m: "≤"),
    ("ge", re.compile(r"(?<=\s)(>=|≥)(?=\s)"), lambda m: ">"),
    ("gt", re.compile(r"(?<=\s)>(?=\s)"), lambda m: "≥"),
    ("bool", re.compile(r"\b(true|false)\b"), lambda m: "false" if m.group(1) == "true" else "true"),
    ("num", re.compile(r"(?<![\w.'])(\d+)(?![\w.])"), lambda m: str(int(m.group(1)) + 1)),
]


def code_mask(src):
    """For each character, True if it is code: not in a comment and not on an import/open line."""
    mask = [True] * len(src)
    i, n, in_str = 0, len(src), False
    while i < n:
        c = src[i]
        if in_str:
            if c == "\\": i += 2; continue
            if c == '"': in_str = False
            i += 1; continue
        if c == '"': in_str = True; i += 1; continue
        if src.startswith("--", i):
            j = src.find("\n", i); j = n if j < 0 else j
            for k in range(i, j): mask[k] = False
            i = j; continue
        if src.startswith("/-", i):  # block, doc and module comments (nested)
            depth, j = 0, i
            while j < n:
                if src.startswith("/-", j): depth += 1; j += 2; continue
                if src.startswith("-/", j):
                    depth -= 1; j += 2
                    if depth == 0: break
                    continue
                j += 1
            for k in range(i, j): mask[k] = False
            i = j; continue
        i += 1
    pos = 0
    for line in src.split("\n"):
        if re.match(r"\s*(import|open|namespace|end|set_option)\b", line):
            for k in range(pos, pos + len(line)): mask[k] = False
        pos += len(line) + 1
    return mask


def sites(path):
    """Every (file, start, end, operator, original, replacement, line) mutation site in a file."""
    src = open(path).read()
    mask = code_mask(src)
    out = []
    for name, rx, rep in OPERATORS:
        for m in rx.finditer(src):
            if not mask[m.start()]: continue
            new = rep(m)
            if new == m.group(0): continue
            out.append((path, m.start(), m.end(), name, m.group(0), new, src.count("\n", 0, m.start()) + 1))
    out.sort(key=lambda s: (s[0], s[1], s[3]))
    return out


def sample(all_sites, k):
    if len(all_sites) <= k: return all_sites
    return [all_sites[(i * len(all_sites)) // k] for i in range(k)]


def lake_build(impl, target):
    p = subprocess.run(["lake", "build", target], cwd=impl, capture_output=True, text=True)
    return p.returncode == 0, p.stdout + p.stderr


def exe_for_root(impl, root):
    """The `lean_exe` target whose root module is `root`, and the path of the binary it builds."""
    text = open(os.path.join(impl, "lakefile.lean")).read()
    for m in re.finditer(r"lean_exe\s+(\S+)\s+where(.*?)(?=\n\S|\Z)", text, re.S):
        r = re.search(r"root\s*:=\s*`(\S+)", m.group(2))
        if r and r.group(1) == root:
            e = re.search(r'exeName\s*:=\s*"([^"]+)"', m.group(2))
            name = e.group(1) if e else m.group(1)
            return m.group(1), os.path.join(impl, ".lake", "build", "bin", name)
    print(f"selftest: no lean_exe with root `{root}` in {impl}/lakefile.lean"); sys.exit(2)


def difftest(sut, oracle, gen, runs, length, timeout, shrink):
    args = [sys.executable, "-I", DIFFTEST, "--sut", sut, "--oracle", oracle, "--gen", gen,
            "--runs", str(runs), "--length", str(length), "--timeout", str(timeout)]
    if not shrink: args.append("--no-shrink")
    p = subprocess.run(args, capture_output=True, text=True)
    return p.returncode == 0, (p.stdout + p.stderr).strip()


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--impl", required=True)
    ap.add_argument("--cli-root", required=True, help="root module of the CLI executable (serves `<dir> serve`)")
    ap.add_argument("--oracle-root", required=True, help="root module of the model oracle executable")
    ap.add_argument("--gen", required=True, help="generator, relative to --impl")
    ap.add_argument("--file", action="append", required=True, help="shell source to mutate, relative to --impl")
    ap.add_argument("--runs", type=int, default=20)
    ap.add_argument("--length", type=int, default=200)
    ap.add_argument("--min-score", type=float, default=0.7)
    ap.add_argument("--max-mutants", type=int, default=30)
    ap.add_argument("--timeout", type=int, default=30, help="seconds per sequence (a hung mutant is killed)")
    ap.add_argument("--test", action="append", default=[],
                    help="the app's own test of the CLI, relative to --impl (e.g. tests/cli_test.sh); a mutant it fails is killed")
    a = ap.parse_args()
    impl = os.path.abspath(a.impl)
    cli_target, cli = exe_for_root(impl, a.cli_root)
    oracle_target, oracle_bin = exe_for_root(impl, a.oracle_root)
    files = [os.path.join(impl, f) for f in a.file]
    gen = os.path.join(impl, a.gen)
    for f in files + [gen]:
        if not os.path.isfile(f): print(f"selftest: {f} not found"); sys.exit(2)
    originals = {f: open(f).read() for f in files}
    stale = [f for f in files if os.path.exists(f + ".mil-orig")]
    if stale:
        print(f"selftest: an earlier run was interrupted; restore from {stale[0]}.mil-orig first"); sys.exit(2)
    for f in files: shutil.copyfile(f, f + ".mil-orig")

    def restore(*_):
        for f, s in originals.items():
            open(f, "w").write(s)
            if os.path.exists(f + ".mil-orig"): os.remove(f + ".mil-orig")
    signal.signal(signal.SIGTERM, lambda *_: (restore(), sys.exit(1)))

    report = {"runs": a.runs, "length": a.length, "min_score": a.min_score, "files": a.file}
    ok = False
    tmp = tempfile.mkdtemp(prefix="mil-selftest-")
    try:
        for t in (cli_target, oracle_target):
            built, log = lake_build(impl, t)
            if not built: print(f"selftest: `lake build {t}` failed:\n{log[-2000:]}"); sys.exit(1)
        oracle = os.path.join(tmp, "oracle")
        shutil.copy2(oracle_bin, oracle)
        sut = f"{cli} {{dir}} serve"
        agree, out = difftest(sut, oracle, gen, a.runs, a.length, a.timeout, True)
        report["difftest"] = {"passed": agree, "output": out.splitlines()[-12:]}
        print(out.splitlines()[-1] if agree else out)
        if not agree:
            print("selftest: FAILED (the shell disagrees with the model)"); return
        def tests_pass():
            for t in a.test:
                try:
                    p = subprocess.run([os.path.join(impl, t)], cwd=impl, capture_output=True, text=True, timeout=600)
                except subprocess.TimeoutExpired:
                    return False, f"{t}: timed out"
                if p.returncode != 0: return False, (p.stdout + p.stderr).strip()
            return True, ""
        good, out = tests_pass()
        report["tests"] = {"commands": a.test, "passed": good}
        if not good:
            print(f"selftest: FAILED (the app's own test fails on the unmutated shell):\n{out[-1500:]}"); return
        chosen = sample([s for f in files for s in sites(f)], a.max_mutants)
        built_n, killed, survived, unbuilt = 0, 0, [], 0
        for (f, st, en, op, old, new, line) in chosen:
            src = originals[f]
            open(f, "w").write(src[:st] + new + src[en:])
            try:
                b, _ = lake_build(impl, cli_target)
                if not b: unbuilt += 1; continue
                built_n += 1
                # a short run kills most mutants; only one that survives it gets the full run
                agree, _ = difftest(sut, oracle, gen, max(3, a.runs // 4), a.length, a.timeout, False)
                if agree: agree, _ = tests_pass()
                if agree: agree, _ = difftest(sut, oracle, gen, a.runs, a.length, a.timeout, False)
                rel = os.path.relpath(f, impl)
                if agree: survived.append({"file": rel, "line": line, "operator": op, "from": old, "to": new})
                else: killed += 1
            finally:
                open(f, "w").write(src)
        score = killed / built_n if built_n else 0.0
        report["mutants"] = {"sites_sampled": len(chosen), "built": built_n, "did_not_build": unbuilt,
                             "killed": killed, "score": round(score, 3), "survived": survived}
        print(f"selftest: {len(chosen)} mutants, {built_n} built, {killed} killed, score {score:.2f} (minimum {a.min_score})")
        for s in survived:
            print(f"  survived: {s['file']}:{s['line']} {s['operator']} {s['from']} -> {s['to']}")
        ok = built_n > 0 and score >= a.min_score
        if built_n == 0: print("selftest: FAILED (no mutant built: nothing shows the test can fail)")
        elif not ok: print("selftest: FAILED (mutation score below the minimum: the tests miss changes to the shell)")
    except KeyboardInterrupt:
        print("selftest: interrupted")
    finally:
        restore()
        shutil.rmtree(tmp, ignore_errors=True)
        rebuilt, _ = lake_build(impl, cli_target)  # the binary matches the restored source again
        report["passed"] = ok and rebuilt
        os.makedirs(os.path.join(impl, ".mil"), exist_ok=True)
        with open(os.path.join(impl, ".mil", "selftest.json"), "w") as fh:
            json.dump(report, fh, indent=2)
    if report["passed"]: print("selftest: PASSED")
    return report["passed"]


if __name__ == "__main__":
    # every early return (a failed build, a disagreement, a failing test) returns None: a failure
    sys.exit(0 if main() is True else 1)
