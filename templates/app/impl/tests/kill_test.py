#!/usr/bin/env python3
"""Stage 5 crash test on real files: SIGKILL the CLI at random moments and check that the state
after recovery is exactly the acknowledged commands, plus possibly the killed one, applied in full.
Usage: python3 tests/kill_test.py [commands] [seed]   (from impl/, after `lake build appnameCli`)"""
import os, random, signal, subprocess, sys, tempfile, time

BIN = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".lake", "build", "bin", "appname")

def run(d, *args):
    return subprocess.run([BIN, d, *args], capture_output=True, text=True)

def main():
    n = int(sys.argv[1]) if len(sys.argv) > 1 else 200
    rng = random.Random(int(sys.argv[2]) if len(sys.argv) > 2 else 1)
    killed = applied = 0
    with tempfile.TemporaryDirectory() as d:
        acked = 0  # the model: increments acknowledged so far
        for _ in range(n):
            p = subprocess.Popen([BIN, d, "incr", "k"], stdout=subprocess.PIPE, text=True)
            if rng.random() < 0.5:
                time.sleep(rng.random() * 0.004)
                p.send_signal(signal.SIGKILL)
            out, _ = p.communicate()
            if p.returncode == 0:
                acked += 1
                assert out.strip() == f"VALUE {acked}", (out, acked)
                continue
            killed += 1
            # Killed: the increment is applied in full or not at all, never anything else.
            v = int(run(d, "get", "k").stdout.split()[1])
            assert v in (acked, acked + 1), (v, acked)
            if v == acked + 1:
                applied += 1
                acked = v
    print(f"kill_test: {n} commands, {killed} killed ({applied} applied before the kill), all consistent")

if __name__ == "__main__":
    main()
