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


def main():
    # a cancelled run (SIGTERM, e.g. a CI timeout) still cleans up: turn it into a normal exit
    signal.signal(signal.SIGTERM, lambda *_: sys.exit(143))
    remove_stale()
    # detached (no branch is created) and named by process id (never an active worktree's name)
    wt = os.path.join(M, ".claude", "worktrees", f"guardtest-{os.getpid()}")
    subprocess.run(["git", "-C", M, "worktree", "add", "-q", "--detach", wt, "HEAD"], check=True)
    try:
        all_cases = cases(M, "main") + cases(wt, "worktree")
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


if __name__ == "__main__":
    main()
