#!/usr/bin/env python3
"""Differential test: a system under test against the Lean reference-model oracle.

Both sides speak the app's line protocol: one command per stdin line, one answer per stdout line.
The driver generates random command sequences, runs each through both, and requires identical
answers. A mismatch is shrunk to a short failing sequence and printed.

    python3 tools/difftest.py --sut 'examples/counter/impl/.lake/build/bin/counter {dir} serve' \\
        --oracle examples/counter/impl/.lake/build/bin/counter-oracle \\
        --gen examples/counter/impl/tests/gen_commands.py --runs 50 --length 200

  --sut     command for the system under test; `{dir}` is replaced by a fresh empty directory per
            run (the system's state lives there). For a non-Lean shell, point this at an adapter
            that speaks the line protocol and talks to the shell (for example over HTTP).
  --oracle  command for the oracle (`<app>-oracle`: the frozen spec's model, from the empty state).
  --gen     a Python file defining `gen(rng, n) -> list[str]`: n protocol lines, drawn with `rng`
            (a `random.Random`). It should reach every command, every error and every limit.

Exit 0 when every run agrees; 1 on the first disagreement (after shrinking); 2 on usage errors.
"""
import argparse, importlib.util, random, shlex, subprocess, sys, tempfile


def run(cmd, lines, tmp_root):
    with tempfile.TemporaryDirectory(dir=tmp_root) as d:
        argv = [a.replace("{dir}", d + "/state") for a in shlex.split(cmd)]
        p = subprocess.run(argv, input="".join(l + "\n" for l in lines), capture_output=True, text=True, timeout=600)
        return p.stdout.splitlines(), p.returncode, p.stderr


def disagree(sut, oracle, lines, tmp_root):
    """None if both sides agree on `lines`, else a description of the first difference."""
    a, rc_a, err_a = run(sut, lines, tmp_root)
    b, _, _ = run(oracle, lines, tmp_root)
    for i, line in enumerate(lines):
        x = a[i] if i < len(a) else f"<no answer; exit {rc_a}; stderr: {err_a.strip()[:200]}>"
        y = b[i] if i < len(b) else "<no answer>"
        if x != y:
            return i, x, y
    if len(a) != len(b):
        return len(lines), f"{len(a)} answer lines", f"{len(b)} answer lines"
    return None


def shrink(sut, oracle, lines, tmp_root):
    """A shorter sequence that still disagrees: cut after the first difference, then drop lines."""
    i, _, _ = disagree(sut, oracle, lines, tmp_root)
    lines = lines[: i + 1]
    k = 0
    while k < len(lines) - 1:
        trial = lines[:k] + lines[k + 1:]
        if disagree(sut, oracle, trial, tmp_root):
            lines = trial
        else:
            k += 1
    return lines


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--sut", required=True)
    ap.add_argument("--oracle", required=True)
    ap.add_argument("--gen", required=True)
    ap.add_argument("--runs", type=int, default=50)
    ap.add_argument("--length", type=int, default=200)
    ap.add_argument("--seed", type=int, default=1)
    args = ap.parse_args()
    spec = importlib.util.spec_from_file_location("difftest_gen", args.gen)
    if spec is None or spec.loader is None:
        print(f"cannot load generator {args.gen}"); sys.exit(2)
    gen = importlib.util.module_from_spec(spec); spec.loader.exec_module(gen)
    with tempfile.TemporaryDirectory() as tmp_root:
        total = 0
        for r in range(args.runs):
            rng = random.Random(args.seed * 1_000_003 + r)
            lines = gen.gen(rng, args.length)
            total += len(lines)
            if disagree(args.sut, args.oracle, lines, tmp_root):
                small = shrink(args.sut, args.oracle, lines, tmp_root)
                i, got, want = disagree(args.sut, args.oracle, small, tmp_root)
                print(f"difftest: DISAGREEMENT in run {r} (seed {args.seed}), shrunk to {len(small)} commands:")
                for j, l in enumerate(small):
                    print(f"  {'>>' if j == i else '  '} {l}")
                print(f"  system answered: {got}\n  oracle answered: {want}")
                sys.exit(1)
        print(f"difftest: {args.runs} runs, {total} commands, system and oracle agree on every answer")


if __name__ == "__main__":
    main()
