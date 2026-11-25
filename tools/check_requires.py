#!/usr/bin/env python3
"""Every `require … from "path"` in a tracked lakefile names a path git tracks.

A require that points at an untracked or git-ignored directory (e.g. bench/verina/runs/) builds on
the machine that made it and breaks every fresh clone, including CI. Template lakefiles are skipped
(their paths hold the MIL_ROOT placeholder). Git-URL requires (`from git "…"`) are not paths.
"""
import os, re, subprocess, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
REQ = re.compile(r'^\s*require\s+\S+\s+from\s+"([^"]+)"', re.M)


def git(*args):
    return subprocess.run(["git", "-C", ROOT, *args], capture_output=True, text=True, check=True).stdout


def main():
    bad, n = [], 0
    for lf in git("ls-files", "*lakefile.lean").split():
        if lf.startswith("templates/"):
            continue
        for path in REQ.findall(open(os.path.join(ROOT, lf)).read()):
            n += 1
            target = os.path.relpath(os.path.normpath(os.path.join(ROOT, os.path.dirname(lf), path)), ROOT)
            if target.startswith("..") or not git("ls-files", "--", target).strip():
                bad.append(f"{lf}: require from \"{path}\" -> {target} is not tracked by git")
    if bad:
        print("\n".join(bad))
        print(f"check_requires: FAILED ({len(bad)} of {n} requires name untracked paths; a fresh clone will not build)")
        sys.exit(1)
    print(f"check_requires: OK ({n} requires, all tracked)")


if __name__ == "__main__":
    main()
