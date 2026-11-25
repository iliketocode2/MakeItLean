#!/usr/bin/env python3
"""Regression test for the guard hooks (guard_locked.py, guard_role.py).

Feeds each hook the JSON Claude Code would send and checks it allows or blocks as intended, in
the main checkout and in a throwaway git worktree, from either working directory. It includes the
exact commands that were falsely blocked during the Phase 3 exit test (read-only redirects, a
`cd` before a relative path, heredocs that only mention a frozen path).

    python3 -I tools/hooks/test_guards.py      (from anywhere; exit 0 when every case passes)
"""
import json, os, signal, subprocess, sys

HOOKS = os.path.dirname(os.path.abspath(__file__))
M = os.path.realpath(os.path.join(HOOKS, "..", ".."))
SPEC = "examples/ledger/Ledger/Spec/Model.lean"   # frozen (ledger-v1)
LAKE = "examples/ledger/lakefile.lean"             # frozen
IMPL_LAKE = "examples/ledger/impl/lakefile.lean"   # not frozen


def hook(name, payload):
    return subprocess.run([sys.executable, "-I", os.path.join(HOOKS, name)], input=json.dumps(payload),
                          capture_output=True, text=True).returncode


def cases(root, label):
    out = []
    for cwd, cl in [(M, "cwd=main"), (root, "cwd=own")]:
        L = lambda tool, inp, want, d: out.append(("guard_locked.py", {"tool_name": tool, "cwd": cwd, "tool_input": inp}, want, f"{label} {cl}: {d}"))
        R = lambda role, tool, inp, want, d: out.append(("guard_role.py", {"agent_type": role, "tool_name": tool, "cwd": cwd, "tool_input": inp}, want, f"{label} {cl}: {role} {d}"))
        f = lambda rel: os.path.join(root, rel)
        # frozen files, every agent
        L("Edit", {"file_path": f(SPEC)}, 2, "edit frozen spec")
        L("Bash", {"command": f"echo x > {f(SPEC)}"}, 2, "shell-overwrite frozen spec")
        L("Bash", {"command": f"rm -rf {f('examples/ledger/Ledger')}"}, 2, "delete a directory holding frozen files")
        L("Bash", {"command": f"cd {f('examples/ledger')} && python3 - <<EOF\nopen('lakefile.lean','w')\nEOF"}, 2, "inline python writes frozen lakefile after cd")
        L("Edit", {"file_path": f(IMPL_LAKE)}, 0, "edit unfrozen impl lakefile")
        L("Bash", {"command": f"cat {f(SPEC)} > /dev/null"}, 0, "read frozen spec, stdout to /dev/null")
        L("Bash", {"command": f"grep x {f(SPEC)} 2>&1 | head"}, 0, "read frozen spec with 2>&1")
        L("Bash", {"command": f"python3 -c \"open('{f(SPEC)}','w')\""}, 2, "python -c writes frozen spec")
        L("Bash", {"command": f"python3 - {f(SPEC)} <<'PY'\nimport sys; open(sys.argv[1],'w')\nPY"}, 2, "inline python writes a frozen file passed as an argument")
        L("Bash", {"command": f"grep -n require {f(LAKE)}; python3 -c \"open('{f(LAKE)}','w')\""}, 2, "read, then python -c writes the same frozen file")
        # Phase 5 false positive: a read in one segment, unrelated inline python in another
        L("Bash", {"command": f"grep -n require {f(LAKE)}; python3 -c \"import json; print(json.load(open('mil.json')))\""}, 0, "grep a frozen file, then unrelated python -c (was a false block)")
        # Phase 3 false positives
        L("Bash", {"command": f"cd {f('examples/ledger/impl')} && python3 - <<EOF\nopen('lakefile.lean','w')\nEOF"}, 0, "inline python edits impl lakefile after cd (was a false block)")
        L("Bash", {"command": f"cat > /tmp/notes.md <<'EOF'\nmentions {LAKE} and {SPEC} > x\nEOF"}, 0, "heredoc to scratch only mentions frozen paths (was a false block)")
        # roles
        R("mil-implementer", "Write", {"file_path": f("examples/ledger/http/server.ts")}, 0, "writes http/server.ts")
        R("mil-implementer", "Write", {"file_path": f("examples/ledger/http/REQUIREMENTS.md")}, 2, "writes http/REQUIREMENTS.md")
        R("mil-spec-author", "Write", {"file_path": f("examples/ledger/http/REQUIREMENTS.md")}, 0, "writes http/REQUIREMENTS.md")
        R("mil-spec-author", "Write", {"file_path": f("examples/ledger/http/server.ts")}, 2, "writes http/server.ts")
        R("mil-implementer", "Edit", {"file_path": f("lean/MakeItLean/Gates.lean")}, 2, "edits framework")
        R("mil-implementer", "Bash", {"command": f"sed -i s/a/b/ {f(SPEC)}"}, 2, "shell-edits spec")
        R("mil-implementer", "Bash", {"command": f"cd {f('examples/ledger/impl')} && lake build 2>&1 | tail -1"}, 0, "lake build with 2>&1 (was a false block)")
        R("mil-auditor", "Bash", {"command": f"grep -rn x {f('cli')} 2>/dev/null"}, 0, "grep with 2>/dev/null (was a false block)")
        R("mil-spec-author", "Bash", {"command": f"sed -n 's/a/b/p' {f(SPEC)}"}, 0, "sed without -i (was a false block)")
        # inline interpreter code that names a file counts as a possible write (it could open it
        # for writing); read-only probes go through the Read tool or a saved script instead
        R("mil-auditor", "Bash", {"command": f"node -e 'x => x' {f('examples/ledger/http/server.ts')} > /dev/null"}, 2, "inline node code naming another role's file")
        R("mil-auditor", "Bash", {"command": "node /tmp/probe.mjs > /dev/null"}, 0, "runs a saved probe script")
        # an inline script whose `cd` names the repository root is not a write to every file in it
        L("Bash", {"command": f"cd {root} && python3 - <<EOF\nprint(open('{IMPL_LAKE}').read())\nEOF"}, 0, "inline python after cd to the root (was a false block)")
        R("mil-prover", "Bash", {"command": f"cd {f('examples/ledger/impl')} && echo x > LedgerImpl/Core.lean"}, 2, "overwrites Core after cd")
    return out


def remove_stale():
    """Remove throwaway worktrees left by earlier runs that were killed (their process is gone)."""
    base = os.path.join(M, ".claude", "worktrees")
    for name in os.listdir(base) if os.path.isdir(base) else []:
        if name.startswith("guardtest-"):
            pid = name.split("-", 1)[1]
            alive = pid.isdigit() and os.path.exists(f"/proc/{pid}")
            if not alive:
                subprocess.run(["git", "-C", M, "worktree", "remove", "--force", os.path.join(base, name)],
                               check=False, capture_output=True)
    subprocess.run(["git", "-C", M, "worktree", "prune"], check=False)


def bench_app_cases(app):
    """An app outside examples/ (found by its mil.json), shell variables, and templates/."""
    out = []
    R = lambda role, tool, inp, want, d: out.append(("guard_role.py", {"agent_type": role, "tool_name": tool, "cwd": M, "tool_input": inp}, want, f"bench app: {role} {d}"))
    R("mil-spec-author", "Write", {"file_path": f"{app}/Zt/Spec/Model.lean"}, 0, "writes the spec of an app under bench/ (was blocked)")
    R("mil-spec-author", "Write", {"file_path": f"{app}/FRICTION.md"}, 0, "writes the bench app's FRICTION.md")
    R("mil-implementer", "Write", {"file_path": f"{app}/Zt/Spec/Model.lean"}, 2, "writes the bench app's spec")
    R("mil-prover", "Write", {"file_path": f"{app}/impl/ZtImpl/Proofs.lean"}, 0, "writes the bench app's proofs")
    R("mil-spec-author", "Bash", {"command": "S=/tmp/scratch-x; mkdir -p $S; echo x > $S/Draft.lean"}, 0, "writes a scratch file through a shell variable (was blocked)")
    R("mil-spec-author", "Bash", {"command": f"F={app}/impl/ZtImpl/Core.lean; echo x > $F"}, 2, "writes another role's file through a shell variable")
    R("mil-spec-author", "Write", {"file_path": f"{M}/templates/pure/AppName/Spec/Model.lean"}, 2, "writes the template (framework, despite its mil.json)")
    return out


def read_cases():
    """guard_read.py: subagents cannot see the hidden benchmark directory (MIL_PROTECTED_READS)."""
    B = os.path.realpath(os.path.expanduser("~/bench"))
    out = []
    G = lambda payload, want, d: out.append(("guard_read.py", payload, want, f"read guard: {d}"))
    sub = {"agent_type": "mil-implementer", "cwd": M}
    G({**sub, "tool_name": "Read", "tool_input": {"file_path": f"{B}/verina/datasets/verina/x/task.lean"}}, 2, "subagent reads a reference file")
    G({**sub, "tool_name": "Grep", "tool_input": {"pattern": "postcond", "path": f"{B}/verina"}}, 2, "subagent greps the dataset")
    G({**sub, "tool_name": "Glob", "tool_input": {"pattern": "~/bench/**/*.lean"}}, 2, "subagent globs the dataset")
    G({**sub, "tool_name": "Bash", "tool_input": {"command": "cat ~/bench/verina/datasets/verina/x/test.json"}}, 2, "subagent cats a test file")
    G({**sub, "tool_name": "Bash", "tool_input": {"command": "git clone https://github.com/sunblaze-ucb/verina /tmp/v"}}, 2, "subagent clones the benchmark")
    G({**sub, "tool_name": "WebSearch", "tool_input": {"query": "verina isOddAtIndexOdd solution"}}, 2, "subagent searches the web for it")
    G({**sub, "tool_name": "Read", "tool_input": {"file_path": f"{M}/bench/verina/runs/x/REQUIREMENTS.md"}}, 0, "subagent reads its own run directory")
    G({**sub, "tool_name": "Bash", "tool_input": {"command": "lake build 2>&1 | tail -1"}}, 0, "subagent builds")
    G({"cwd": M, "tool_name": "Read", "tool_input": {"file_path": f"{B}/verina/datasets/verina/x/task.lean"}}, 0, "main session reads the dataset (the scorer's side)")
    return out


def external_cases(base):
    """Apps outside the framework checkout (Phase 5 W2): one in its own git repository, one in no
    repository at all. Their frozen files and role areas must be protected all the same."""
    out = []
    for kind in ("git", "nogit"):
        repo = os.path.join(base, kind)
        app = os.path.join(repo, "myapp")
        os.makedirs(os.path.join(app, "MyApp", "Spec"), exist_ok=True)
        os.makedirs(os.path.join(app, "impl", "MyAppImpl"), exist_ok=True)
        if kind == "git":
            subprocess.run(["git", "init", "-q", repo], check=True)
        open(os.path.join(app, "mil.json"), "w").write("{}\n")
        open(os.path.join(app, "MyApp", "Spec", "Model.lean"), "w").write("-- spec\n")
        open(os.path.join(app, "spec.lock"), "w").write("# Frozen spec. Signed off by: test\n0  MyApp/Spec/Model.lean\n0  mil.json\n")
        spec, impl = os.path.join(app, "MyApp", "Spec", "Model.lean"), os.path.join(app, "impl", "MyAppImpl", "Core.lean")
        L = lambda tool, inp, want, d: out.append(("guard_locked.py", {"tool_name": tool, "cwd": repo, "tool_input": inp}, want, f"external {kind}: {d}"))
        R = lambda role, tool, inp, want, d: out.append(("guard_role.py", {"agent_type": role, "tool_name": tool, "cwd": repo, "tool_input": inp}, want, f"external {kind}: {role} {d}"))
        L("Edit", {"file_path": spec}, 2, "edit frozen spec file")
        L("Write", {"file_path": os.path.join(app, "mil.json")}, 2, "write frozen mil.json")
        L("Write", {"file_path": os.path.join(app, "spec.lock")}, 2, "write spec.lock itself")
        L("Bash", {"command": "echo x > myapp/MyApp/Spec/Model.lean"}, 2, "redirect into frozen spec file")
        L("Edit", {"file_path": impl}, 0, "edit unfrozen impl file")
        R("mil-implementer", "Edit", {"file_path": spec}, 2, "edits the spec area")
        R("mil-implementer", "Write", {"file_path": impl}, 0, "writes the impl area")
    return out


def main():
    # a cancelled run (SIGTERM, e.g. a CI timeout) still cleans up: turn it into a normal exit
    signal.signal(signal.SIGTERM, lambda *_: sys.exit(143))
    remove_stale()
    # detached (no branch is created) and named by process id (never an active worktree's name)
    wt = os.path.join(M, ".claude", "worktrees", f"guardtest-{os.getpid()}")
    subprocess.run(["git", "-C", M, "worktree", "add", "-q", "--detach", wt, "HEAD"], check=True)
    try:
        app = os.path.join(M, "bench", f"zguardapp-{os.getpid()}")
        os.makedirs(app, exist_ok=True)
        open(os.path.join(app, "mil.json"), "w").write("{}\n")
        import tempfile
        ext = tempfile.mkdtemp(prefix="guardtest-ext-")
        all_cases = (cases(M, "main") + cases(wt, "worktree") + read_cases() + bench_app_cases(app)
                     + external_cases(ext))
        fails = 0
        for name, payload, want, desc in all_cases:
            rc = hook(name, payload)
            if rc != want:
                fails += 1
                print(f"FAIL {name}: exit {rc}, wanted {want}: {desc}")
        print(f"test_guards: {len(all_cases) - fails} passed, {fails} failed")
        sys.exit(1 if fails else 0)
    finally:
        subprocess.run(["git", "-C", M, "worktree", "remove", "--force", wt], check=False)
        import shutil
        shutil.rmtree(os.path.join(M, "bench", f"zguardapp-{os.getpid()}"), ignore_errors=True)
        if "ext" in locals():
            shutil.rmtree(ext, ignore_errors=True)


if __name__ == "__main__":
    main()
