#!/usr/bin/env python3
"""PreToolUse hook: subagents cannot see benchmark answers (Phase 4).

The VERINA dataset (reference code, specs, proofs and the tests used for scoring) lives outside
the repository, under PROTECTED (default `~/bench`). A subagent (any call that carries
`agent_type`: the role agents and the benchmark baseline) may not read, search, list or run a
command that names a path there, and may not fetch the benchmark from the web. The main session,
which runs the scorer, is not restricted. Exit 2 blocks; the reason is shown to the agent.
"""
import json, os, re, sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import shellwrites  # noqa: E402

PROTECTED = [os.path.realpath(os.path.expanduser(p)) for p in
             os.environ.get("MIL_PROTECTED_READS", "~/bench").split(":") if p]
WEB = re.compile(r"verina|sunblaze", re.I)


def protected(path, cwd):
    full = os.path.realpath(os.path.expanduser(path) if path.startswith("~") else
                            path if os.path.isabs(path) else os.path.join(cwd, path))
    return any(full == p or full.startswith(p + "/") for p in PROTECTED)


def deny(why):
    sys.stderr.write(f"BLOCKED: {why}. Benchmark answers and tests are hidden from agents "
                     "(docs/PHASE4.md); work only from the task's REQUIREMENTS.md.\n")
    sys.exit(2)


def main():
    try:
        data = json.load(sys.stdin)
    except Exception:
        sys.exit(0)
    if not data.get("agent_type"):
        sys.exit(0)  # the main session is not restricted
    tool, inp = data.get("tool_name", ""), data.get("tool_input", {}) or {}
    cwd = data.get("cwd") or os.getcwd()
    if tool in ("Read", "Edit", "Write", "MultiEdit", "NotebookEdit"):
        p = inp.get("file_path") or inp.get("notebook_path") or ""
        if p and protected(p, cwd):
            deny(f"{p} is in the hidden benchmark directory")
    elif tool in ("Grep", "Glob"):
        for p in (inp.get("path") or "", inp.get("pattern") or ""):
            if p and ("/" in p or p.startswith("~")) and protected(p.split("*")[0] or ".", cwd):
                deny(f"{p} is in the hidden benchmark directory")
        if not inp.get("path") and protected(cwd, cwd):
            deny("searching inside the hidden benchmark directory")
    elif tool == "Bash":
        cmd = inp.get("command", "")
        if re.search(r"github\.com/sunblaze|huggingface\.co/.*verina", cmd, re.I):
            deny("fetching the benchmark")
        for tok in re.findall(r"[~\w./-]+", cmd):
            if ("/" in tok or tok.startswith("~")) and protected(tok, cwd):
                deny(f"the command names {tok}, in the hidden benchmark directory")
        for t in shellwrites.inline_script_paths(cmd, cwd):
            if protected(t, cwd):
                deny(f"inline code names {t}, in the hidden benchmark directory")
    elif tool in ("WebFetch", "WebSearch"):
        if WEB.search(inp.get("url", "") + " " + inp.get("query", "") + " " + inp.get("prompt", "")):
            deny("looking up the benchmark on the web")
    sys.exit(0)


if __name__ == "__main__":
    main()
