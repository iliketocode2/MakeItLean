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


def root_of(path):
    """The repository (or worktree) holding `path`: its nearest ancestor with judge/ and a
    lakefile. Found from the target, not the agent's working directory, so a worktree's own
    frozen files are protected whatever the agent's cwd is."""
    d = path if os.path.isdir(path) else os.path.dirname(path)
    while d and not os.path.isdir(d):
        d = os.path.dirname(d)
    return repo_root(d) if d else None


def path_tokens(cmd, cwd):
    """Absolute forms of the path-like words in a shell command."""
    out = []
    for tok in re.findall(r"[\w./~-]+", cmd):
        if "/" in tok or "." in tok:
            out.append(os.path.realpath(os.path.expanduser(tok) if tok.startswith("~") else
                                        tok if os.path.isabs(tok) else os.path.join(cwd, tok)))
    return out


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
    if tool in WRITE_TOOLS:
        p = inp.get("file_path") or inp.get("notebook_path")
        if p:
            full = os.path.realpath(p if os.path.isabs(p) else os.path.join(cwd, p))
            root = root_of(full)
            if root:
                frozen = frozen_files(root)
                if full in frozen:
                    block(full, frozen[full], root)
        sys.exit(0)
    if tool != "Bash":
        sys.exit(0)
    # every repository the command can touch: the cwd's, and each named path's
    cmd = inp.get("command", "")
    # redirects that write nothing to a file: to /dev/null, and file-descriptor duplications
    probe = re.sub(r"\d*>>?\s*/dev/null|\d*>&\d+|&>\s*/dev/null", " ", cmd)
    if not BASH_WRITES.search(probe):
        sys.exit(0)
    roots = {r for r in [repo_root(cwd)] + [root_of(t) for t in path_tokens(cmd, cwd)] if r}
    for root in roots:
        for full, lock in frozen_files(root).items():
            rel = os.path.relpath(full, root)
            # the path as written: absolute, relative to its repository, or (only when the
            # command runs in that app's directory) relative to the lock's directory
            names = {full, rel}
            lockdir = os.path.realpath(os.path.dirname(lock))
            if os.path.realpath(cwd) == lockdir:
                names.add(os.path.relpath(full, lockdir))
            if any(n in cmd for n in names):
                block(full, lock, root)
    sys.exit(0)


if __name__ == "__main__":
    main()
