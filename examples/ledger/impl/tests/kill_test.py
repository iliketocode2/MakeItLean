#!/usr/bin/env python3
"""Stage 5 crash test for the `ledger` CLI on real files (REQUIREMENTS.md R15, R16).

Runs random commands, SIGKILLing some of them at a random moment. A Python copy of the
reference model tracks the acknowledged commands. After every command (finished or killed) the
ledger is read back with `accounts` and must equal the model after the acknowledged commands,
or, if the last command was killed, possibly after it too. A transfer is never half-applied, and
the total always equals deposits minus withdrawals of the applied commands.

Usage: tests/kill_test.py [iterations] [seed]   (from examples/ledger/impl)
"""
import os, random, signal, subprocess, sys, tempfile, time

MAX = 2**63 - 1
BIN = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".lake", "build", "bin", "ledger")


def step(state, cmd):
    """Reference model (mirrors Ledger.Spec.cstep for the commands used here)."""
    s = dict(state)
    op = cmd[0]
    if op == "open":
        if cmd[1] in s:
            return state, False
        s[cmd[1]] = 0
    elif op == "deposit":
        n, a = cmd[1], cmd[2]
        if n not in s or s[n] + a > MAX:
            return state, False
        s[n] += a
    elif op == "withdraw":
        n, a = cmd[1], cmd[2]
        if n not in s or s[n] < a:
            return state, False
        s[n] -= a
    elif op == "transfer":
        f, t, a = cmd[1], cmd[2], cmd[3]
        if f == t or f not in s or t not in s or s[f] < a or s[t] + a > MAX:
            return state, False
        s[f] -= a
        s[t] += a
    return s, True


def read_back(d):
    out = subprocess.run([BIN, d, "accounts"], capture_output=True, text=True)
    assert out.returncode == 0, out
    w = out.stdout.split()
    assert w[0] == "ACCOUNTS"
    n = int(w[1])
    return {w[2 + 2 * i]: int(w[3 + 2 * i]) for i in range(n)}


def total(cmd_state):
    return sum(cmd_state.values())


def main():
    iters = int(sys.argv[1]) if len(sys.argv) > 1 else 300
    rng = random.Random(int(sys.argv[2]) if len(sys.argv) > 2 else 1)
    names = ["a", "b", "c", "d"]
    with tempfile.TemporaryDirectory() as d:
        model = {}
        net = 0          # deposits − withdrawals of applied commands
        kills = ambiguous = 0
        for i in range(iters):
            r = rng.random()
            if r < 0.1:
                cmd = ("open", rng.choice(names))
            elif r < 0.35:
                cmd = ("deposit", rng.choice(names), rng.randint(1, 1000))
            elif r < 0.5:
                cmd = ("withdraw", rng.choice(names), rng.randint(1, 500))
            else:
                cmd = ("transfer", rng.choice(names), rng.choice(names), rng.randint(1, 800))
            args = [BIN, d] + [str(x) for x in cmd]
            p = subprocess.Popen(args, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
            kill = rng.random() < 0.5
            if kill:
                time.sleep(rng.random() * 0.004)
                p.send_signal(signal.SIGKILL)
            out, _ = p.communicate()
            after, ok = step(model, cmd)
            delta = 0
            if ok and cmd[0] == "deposit":
                delta = cmd[2]
            if ok and cmd[0] == "withdraw":
                delta = -cmd[2]
            got = read_back(d)
            if p.returncode in (0, 1) and out:
                # Acknowledged: the answer was printed; the effect must be visible.
                assert got == after, (i, cmd, got, after)
                model, net = after, net + delta
            else:
                kills += 1
                # Killed: the ledger is the state before, or the state after, never in between.
                if got == after and after != model:
                    model, net = after, net + delta
                    ambiguous += 1
                else:
                    assert got == model, (i, cmd, got, model, after)
            assert total(got) == net, (i, total(got), net)
        print(f"kill_test: {iters} commands, {kills} killed ({ambiguous} applied before the kill), all consistent")


if __name__ == "__main__":
    main()
