// V6: HTTP kill test (http/REQUIREMENTS.md H14, H-D9).
//
//   node examples/ledger/http/tests/kill_test.ts [runs] [requests] [seed]     (default 2 300 1)
//
// Each run uses one directory. Random requests are sent one at a time; at random moments the
// server and its ledger process are both killed with SIGKILL while a request may be in flight.
// The server is then restarted on the same directory and the ledger is read back with
// /accounts and /total. It must equal the frozen model (`ledger-oracle`) after exactly the
// commands that got a response, plus possibly the one in flight, and nothing in between. Every
// response that did arrive must also equal the model's answer.

import * as fs from 'node:fs';
import * as path from 'node:path';
import { startServer, request, lineToRequest, responseToLine, oracle, tmpdir, rng, check, summary } from './lib.ts';
import type { Running } from './lib.ts';

const MAX = '9223372036854775807';

function genLine(r: () => number): string {
  const names = ['a', 'b', 'c', 'd'];
  const n = () => names[Math.floor(r() * names.length)];
  const amt = () => (r() < 0.03 ? MAX : String(1 + Math.floor(r() * 900)));
  const x = r();
  if (x < 0.12) return `open ${n()}`;
  if (x < 0.4) return `deposit ${n()} ${amt()}`;
  if (x < 0.55) return `withdraw ${n()} ${amt()}`;
  if (x < 0.9) return `transfer ${n()} ${n()} ${amt()}`;
  if (x < 0.95) return `balance ${n()}`;
  return 'total';
}

/** Child processes of `pid` (the ledger started by the server). */
function children(pid: number): number[] {
  const out: number[] = [];
  for (const e of fs.readdirSync('/proc')) {
    if (!/^\d+$/.test(e)) continue;
    try {
      const stat = fs.readFileSync(`/proc/${e}/stat`, 'utf8');
      const ppid = Number(stat.slice(stat.lastIndexOf(')') + 2).split(' ')[1]);
      if (ppid === pid) out.push(Number(e));
    } catch {}
  }
  return out;
}

async function gone(pid: number): Promise<void> {
  for (let i = 0; i < 500; i++) {
    try {
      process.kill(pid, 0);
    } catch {
      return;
    }
    try {
      // a zombie counts as dead
      if (fs.readFileSync(`/proc/${pid}/stat`, 'utf8').split(') ')[1]?.startsWith('Z')) return;
    } catch {
      return;
    }
    await new Promise((r) => setTimeout(r, 10));
  }
  throw new Error(`process ${pid} did not die`);
}

/** The ledger's state, read back over HTTP, as answer lines of `accounts` and `total`. */
async function readBack(s: Running): Promise<string[]> {
  const out: string[] = [];
  for (const line of ['accounts', 'total']) {
    const q = lineToRequest(line);
    out.push(responseToLine(q, await request(s.port, 'POST', q.path, q.body)));
  }
  return out;
}

async function main(): Promise<number> {
  const runs = Number(process.argv[2] ?? 2);
  const perRun = Number(process.argv[3] ?? 300);
  const r = rng(Number(process.argv[4] ?? 1));
  let kills = 0, inflightKills = 0, appliedInflight = 0, sent = 0;
  for (let run = 0; run < runs; run++) {
    const d = tmpdir();
    const dir = path.join(d, 'ledger');
    let committed: string[] = []; // the commands the ledger has applied (or refused), in order
    let remaining = perRun;
    while (remaining > 0) {
      const s = await startServer(dir);
      const ledgerPid = children(s.proc.pid!)[0];
      // State after restart = model after the committed commands.
      const want = (await oracle([...committed, 'accounts', 'total'])).slice(-2);
      const got = await readBack(s);
      check(JSON.stringify(got) === JSON.stringify(want), `run ${run}: after restart ${got}, model ${want}`);
      // Send a batch of requests, then kill both processes at a random moment.
      const batch = Math.min(remaining, 5 + Math.floor(r() * 40));
      const killAt = Math.floor(r() * batch);
      let killed = false;
      let inflight: string | null = null;
      const answered: [string, string][] = [];
      for (let i = 0; i < batch && !killed; i++) {
        const line = genLine(r);
        if (i === killAt) {
          setTimeout(() => {
            killed = true;
            try { process.kill(ledgerPid, 'SIGKILL'); } catch {}
            try { process.kill(s.proc.pid!, 'SIGKILL'); } catch {}
          }, r() * 6);
        }
        const q = lineToRequest(line);
        sent++;
        try {
          const resp = await request(s.port, 'POST', q.path, q.body);
          // A 5xx is the server reporting the ledger's death: the command is in flight. Any
          // other response is a ledger answer and acknowledges the command.
          if (resp.status >= 500) { inflight = line; break; }
          answered.push([line, responseToLine(q, resp)]);
        } catch {
          inflight = line;
          break;
        }
      }
      if (!killed) {
        // the batch ended before the timer: kill now, with nothing in flight
        await new Promise((res) => setTimeout(res, 10));
      }
      try { process.kill(ledgerPid, 'SIGKILL'); } catch {}
      try { process.kill(s.proc.pid!, 'SIGKILL'); } catch {}
      await s.exited;
      await gone(ledgerPid);
      kills++;
      remaining -= answered.length + (inflight ? 1 : 0);
      // Every answer that arrived is the model's answer.
      const model = await oracle([...committed, ...answered.map(([l]) => l)]);
      answered.forEach(([l, a], i) => {
        const m = model[committed.length + i];
        check(a === m, `run ${run}: ${l} answered ${a}, model ${m}`);
      });
      committed = [...committed, ...answered.map(([l]) => l)];
      if (inflight !== null) {
        inflightKills++;
        // Restart and decide whether the in-flight command was applied: the state must be the
        // model without it, or with it, nothing else.
        const s2 = await startServer(dir);
        const got2 = await readBack(s2);
        s2.proc.kill('SIGTERM');
        await s2.exited;
        const without = (await oracle([...committed, 'accounts', 'total'])).slice(-2);
        const withIt = (await oracle([...committed, inflight, 'accounts', 'total'])).slice(-2);
        const w = JSON.stringify(got2);
        if (w === JSON.stringify(without)) {
          // not applied (or a command that changes nothing)
        } else if (w === JSON.stringify(withIt)) {
          committed.push(inflight);
          appliedInflight++;
        } else {
          check(false, `run ${run}: after killing '${inflight}' the ledger is ${w}; model without ${without}, with ${withIt}`);
          committed.push(inflight); // keep going with something
        }
      }
    }
    fs.rmSync(d, { recursive: true, force: true });
  }
  console.log(`kill_test: ${runs} runs, ${sent} requests, ${kills} kills (${inflightKills} with a request in flight, ` +
    `${appliedInflight} of those applied), ledger always equal to the model`);
  return summary('kill_test');
}

main().then((c) => process.exit(c), (e) => { console.log(`kill_test: ERROR ${e.stack}`); process.exit(1); });
