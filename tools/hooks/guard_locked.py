#!/usr/bin/env python3
"""PreToolUse hook: refuse edits to frozen spec files.

A file is frozen when it is listed in a `spec.lock` (written by `mil freeze` after the user's
sign-off), or is that `spec.lock` itself. Frozen files are never edited; a spec change goes back
to the user for a new sign-off (agents/AGENTS.md, hard rule 1).

Covers the file tools (Edit, Write, MultiEdit, NotebookEdit) exactly, and Bash through
`shellwrites.py` (redirect targets and write commands, with `cd` followed and heredoc bodies
skipped; paths named in inline interpreter code count as possible writes). `mil check-lock`
and `mil audit` remain the detector of record; this hook is prevention.

Exit 0 allows the call; exit 2 blocks it, and the message on stderr is shown to the agent.
"""
import json, os, re, sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import shellwrites  # noqa: E402

WRITE_TOOLS = {"Edit", "Write", "MultiEdit", "NotebookEdit"}
BASH_WRITES = re.compile(r"(>|\btee\b|\bsed\s+-i|\bperl\s+-i|\bmv\b|\bcp\b|\brm\b|\btruncate\b|\bdd\b|\bchmod\b|\bln\b|\bpatch\b|\bgit\s+(checkout|restore|apply|stash)\b|open\([^)]*['\"][wa])")


def repo_root(start):
    """The repository holding `start`: its nearest ancestor that is the framework checkout (holds
    lean/MakeItLean/Gates.lean) or a git repository (a `.git` directory, or a worktree's `.git`
    file), so an app in its own repository outside the framework is protected too. Failing both,
    the nearest app directory (holds mil.json)."""
    d, app = os.path.abspath(start), None
    while True:
        if (os.path.isfile(os.path.join(d, "lean", "MakeItLean", "Gates.lean"))
                or os.path.exists(os.path.join(d, ".git"))):
            return d
        if app is None and os.path.isfile(os.path.join(d, "mil.json")):
            app = d
        parent = os.path.dirname(d)
        if parent == d:
            return app
        d = parent


def root_of(path):
    """The repository (or worktree) holding `path`: its nearest ancestor holding
    lean/MakeItLean/Gates.lean. Found from the target, not the agent's working directory, so a worktree's own
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
    # Bash: the files the command can write (redirect targets, write commands, paths named in
    # inline interpreter code), with `cd` followed and heredoc bodies skipped (shellwrites.py)
    cmd = inp.get("command", "")
    targets = shellwrites.write_targets(cmd, cwd)
    if targets is None:  # unparseable: fall back to "mentions a frozen path and has a write op"
        targets = path_tokens(cmd, cwd) if BASH_WRITES.search(cmd) else []
    # write targets may be directories (rm -r, cp into); inline-code mentions are files only
    checks = [(t, True) for t in targets] + [(t, False) for t in shellwrites.inline_script_paths(cmd, cwd)]
    cache = {}
    for t, as_dir in checks:
        root = root_of(t)
        if not root:
            continue
        if root not in cache:
            cache[root] = frozen_files(root)
        for full, lock in cache[root].items():
            if (shellwrites.touches(t, full) if as_dir else t == full):
                block(full, lock, root)
    sys.exit(0)


if __name__ == "__main__":
    main()
