#!/usr/bin/env python3
"""PreToolUse hook: refuse edits to frozen spec files.

A file is frozen when it is listed in a `spec.lock` (written by `mil freeze` after the user's
sign-off), or is that `spec.lock` itself. Frozen files are never edited; a spec change goes back
to the user for a new sign-off (agents/AGENTS.md, hard rule 1).

Covers the file tools (Edit, Write, MultiEdit, NotebookEdit) exactly, and Bash on a best-effort
basis (a command that names a frozen file together with a write-like operation). `mil check-lock`
and `mil audit` remain the detector of record; this hook is prevention.

Exit 0 allows the call; exit 2 blocks it, and the message on stderr is shown to the agent.
"""
import json, os, re, sys

WRITE_TOOLS = {"Edit", "Write", "MultiEdit", "NotebookEdit"}
BASH_WRITES = re.compile(r"(>|\btee\b|\bsed\s+-i|\bperl\s+-i|\bmv\b|\bcp\b|\brm\b|\btruncate\b|\bdd\b|\bchmod\b|\bln\b|\bpatch\b|\bgit\s+(checkout|restore|apply|stash)\b|open\([^)]*['\"][wa])")


def repo_root(start):
    d = os.path.abspath(start)
    while True:
        if os.path.isdir(os.path.join(d, "judge")) and os.path.isfile(os.path.join(d, "lakefile.lean")):
            return d
        parent = os.path.dirname(d)
        if parent == d:
            return None
        d = parent


def frozen_files(root):
    """Absolute paths of every frozen file under root, mapped to the lock that freezes it."""
    out = {}
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames[:] = [d for d in dirnames if d not in (".lake", ".git", ".claude", "node_modules")]
        if "spec.lock" in filenames:
            lock = os.path.join(dirpath, "spec.lock")
            out[os.path.realpath(lock)] = lock
            with open(lock) as f:
                for line in f:
                    line = line.strip()
                    if not line or line.startswith("#"):
                        continue
                    parts = line.split(None, 1)
                    if len(parts) == 2:
                        out[os.path.realpath(os.path.join(dirpath, parts[1].lstrip("*")))] = lock
    return out


def block(path, lock, root):
    rel = os.path.relpath(path, root)
    sys.stderr.write(
        f"BLOCKED: {rel} is frozen (listed in {os.path.relpath(lock, root)}, signed off by the user). "
        "Frozen spec files are never edited. If the spec is wrong, stop and report it to the user; "
        "a spec change needs a new sign-off.\n")
    sys.exit(2)


def main():
    try:
        data = json.load(sys.stdin)
    except Exception:
        sys.exit(0)
    tool = data.get("tool_name", "")
    inp = data.get("tool_input", {}) or {}
    cwd = data.get("cwd") or os.getcwd()
    root = repo_root(cwd)
    if root is None:
        sys.exit(0)
    frozen = frozen_files(root)
    if not frozen:
        sys.exit(0)
    if tool in WRITE_TOOLS:
        p = inp.get("file_path") or inp.get("notebook_path")
        if p:
            full = os.path.realpath(p if os.path.isabs(p) else os.path.join(cwd, p))
            if full in frozen:
                block(full, frozen[full], root)
    elif tool == "Bash":
        cmd = inp.get("command", "")
        if BASH_WRITES.search(cmd):
            for full, lock in frozen.items():
                rel = os.path.relpath(full, root)
                # the path as written: absolute, relative to the repo, or (only when the command
                # runs in that app's directory) relative to the lock's directory
                names = {full, rel}
                lockdir = os.path.realpath(os.path.dirname(lock))
                if os.path.realpath(cwd) == lockdir:
                    names.add(os.path.relpath(full, lockdir))
                if any(n in cmd for n in names):
                    block(full, lock, root)
    sys.exit(0)


if __name__ == "__main__":
    main()
