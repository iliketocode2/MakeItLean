"""Which files can a shell command write? (shared by the guard hooks)

`write_targets(cmd, cwd)` returns the absolute paths a Bash command may create, change or delete,
as far as the command text shows:

- the command is split into simple commands at `;`, `&&`, `||`, `|`, `&` and newlines, and a
  `cd DIR` changes the directory later paths are resolved against;
- heredoc bodies are data, not commands: they are skipped (a heredoc fed to `cat > FILE` writes
  FILE, which the redirect shows);
- redirects: `> F`, `>> F`, `&> F`, `N> F`, `>| F`, but not `/dev/null` or `>&N` duplications;
- write commands: tee, sed -i, perl -i, cp/mv/install/rsync (destination; mv also its sources),
  rm/rmdir/unlink/truncate/touch/chmod/chown/ln (their operands), dd of=, git checkout/restore
  (paths after `--`).

What it cannot see: a program that writes files by itself (`python3 script.py`, `make`, a
heredoc fed to an interpreter). The guards are prevention for the common cases; `mil check-lock`
and `mil audit` are the detectors of record.
"""
import os, re, shlex

SEPARATORS = {";", "&&", "||", "|", "&", "\n", "|&"}
OPERAND_WRITERS = {"rm", "rmdir", "unlink", "truncate", "touch", "chmod", "chown", "shred"}
DEST_WRITERS = {"cp", "install", "rsync", "ln"}
REDIRECT = re.compile(r"^(\d*|&)(>>?|>\|)$")


def strip_heredocs(cmd):
    """The command without heredoc bodies (the `<<WORD` line is kept, the body and end line are not)."""
    out, lines, i = [], cmd.split("\n"), 0
    while i < len(lines):
        line = lines[i]
        out.append(line)
        delims = re.findall(r"<<-?\s*(['\"]?)([A-Za-z_][A-Za-z0-9_]*)\1", line)
        i += 1
        for _, word in delims:
            while i < len(lines) and lines[i].strip() != word:
                i += 1
            i += 1  # skip the end line
    return "\n".join(out)


def tokens(cmd):
    """Shell words and operators, or None if the command cannot be tokenized."""
    lex = shlex.shlex(cmd, posix=True, punctuation_chars=";&|<>")
    lex.whitespace_split = True
    lex.commenters = "#"
    lex.whitespace = " \t\r"  # keep newlines as separators
    try:
        return list(lex)
    except ValueError:
        return None


def resolve(path, cwd):
    path = os.path.expanduser(path)
    return os.path.realpath(path if os.path.isabs(path) else os.path.join(cwd, path))


def segments(toks):
    seg = []
    for t in toks:
        if t in SEPARATORS or t == "\n":
            if seg:
                yield seg
            seg = []
        else:
            seg.append(t)
    if seg:
        yield seg


def write_targets(cmd, cwd):
    """Absolute paths the command may write, or None if it cannot be parsed (callers decide)."""
    toks = tokens(strip_heredocs(cmd).replace("\n", " ; "))
    if toks is None:
        return None
    # rejoin split redirect operators: shlex gives '2', '>' or '&', '>' or '>', '>' separately
    merged = []
    for t in toks:
        if merged and t in (">", ">>", ">|") and (merged[-1].isdigit() or merged[-1] == "&"):
            merged[-1] = merged[-1] + t
        elif merged and t == ">" and merged[-1] == ">":
            merged[-1] = ">>"
        elif merged and t == "|" and merged[-1] == ">":
            merged[-1] = ">|"
        elif merged and t == "&" and merged[-1] == "|":
            merged[-1] = "|&"
        elif merged and t == "&" and merged[-1] == "&":
            merged[-1] = "&&"
        elif merged and t == "|" and merged[-1] == "|":
            merged[-1] = "||"
        else:
            merged.append(t)
    out, here = [], cwd
    for seg in segments(merged):
        words, k = [], 0
        while k < len(seg):
            t = seg[k]
            if REDIRECT.match(t) or t in (">", ">>", "&>", ">|"):
                target = seg[k + 1] if k + 1 < len(seg) else ""
                if target.startswith("&"):           # >&2 written as '>' '&2'
                    pass
                elif target and target != "/dev/null":
                    out.append(resolve(target, here))
                k += 2
                continue
            if t.startswith(">&") or re.match(r"^\d*>&\d+$", t) or t == "<" or t.startswith("<<"):
                k += 2 if t in ("<", "<<", "<<-", "<<<") else 1
                continue
            words.append(t)
            k += 1
        if not words:
            continue
        # skip `VAR=value` prefixes and common wrappers
        while words and (re.match(r"^[A-Za-z_][A-Za-z0-9_]*=", words[0]) or words[0] in ("sudo", "env", "command", "time", "nice")):
            words = words[1:]
        if not words:
            continue
        prog, args = os.path.basename(words[0]), words[1:]
        operands = [a for a in args if not a.startswith("-")]
        if prog == "cd":
            here = resolve(operands[0], here) if operands else os.path.expanduser("~")
        elif prog == "pushd" and operands:
            here = resolve(operands[0], here)
        elif prog == "tee":
            out += [resolve(a, here) for a in operands]
        elif prog in ("sed", "perl") and any(a.startswith("-i") or a.startswith("--in-place") for a in args):
            # files are the operands after the script (sed: first operand unless -e/-f given)
            ops = operands
            if prog == "sed" and not any(a in ("-e", "-f") or a.startswith("--expression") for a in args):
                ops = ops[1:]
            if prog == "perl":
                ops = [a for a in ops if not a.startswith("s/")]
            out += [resolve(a, here) for a in ops]
        elif prog == "mv":
            out += [resolve(a, here) for a in operands]
        elif prog in DEST_WRITERS and operands:
            out.append(resolve(operands[-1], here))
        elif prog in OPERAND_WRITERS:
            out += [resolve(a, here) for a in operands]
        elif prog == "dd":
            out += [resolve(a[3:], here) for a in args if a.startswith("of=")]
        elif prog == "git" and args[:1] and args[0] in ("checkout", "restore", "rm", "mv", "apply"):
            if "--" in args:
                out += [resolve(a, here) for a in args[args.index("--") + 1:]]
            elif args[0] in ("rm", "mv"):
                out += [resolve(a, here) for a in operands[1:]]
    return out


def touches(target, path):
    """Does writing `target` affect `path` (the same file, or a directory holding it)?"""
    return path == target or path.startswith(target.rstrip("/") + "/")


INTERPRETERS = {"python", "python3", "node", "perl", "ruby", "bash", "sh", "zsh", "lean"}
# a file-like mention: a word with an extension, not a bare directory (`~/MakeItLean`) and not an
# attribute access (`.read`); callers compare these for equality, never containment
PATHLIKE = re.compile(r"(?<![\w.])[\w~/-][\w.~/-]*\.[A-Za-z0-9]+\b")


def inline_script_paths(cmd, cwd):
    """Paths mentioned in inline interpreter code (`python3 - <<EOF`, `python3 -c`, `node -e`),
    resolved against the directory that command runs in. Such code can write files the command
    text does not show, so a guard treats these mentions as possible writes."""
    out, here = [], cwd
    toks = tokens(strip_heredocs(cmd).replace("\n", " ; ")) or []
    for seg in segments(toks):
        words = [w for w in seg if not re.match(r"^[A-Za-z_][A-Za-z0-9_]*=", w)]
        if not words:
            continue
        prog = os.path.basename(words[0])
        if prog == "cd":
            ops = [a for a in words[1:] if not a.startswith("-")]
            here = resolve(ops[0], here) if ops else os.path.expanduser("~")
            continue
        inline = prog in INTERPRETERS and (
            any(a in ("-c", "-e", "-", "--eval") for a in words[1:]) or "<<" in cmd)
        if inline:
            out += [resolve(m, here) for m in PATHLIKE.findall(cmd) if not m.startswith("-")]
    return out
