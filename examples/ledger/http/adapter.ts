// Line-protocol adapter for the differential test of the HTTP API (http/REQUIREMENTS.md V2).
//
//   node examples/ledger/http/adapter.ts <dir> [--server PATH] [--ledger PATH]
//
// Starts the HTTP server (`server.ts`, or another server file for the planted-bug check, V3) on
// <dir> with `--port 0`, then reads protocol lines on stdin. Each line becomes one HTTP request
// (tests/lib.ts `lineToRequest`), sent one at a time, and each response is printed as the
// answer line it stands for (`responseToLine`, the inverse of H10). `tools/difftest.py` compares
// these lines with `ledger-oracle`'s. At end of input the server is stopped with SIGTERM (H3).
// Trusted test code; Node.js standard library only.

import * as http from 'node:http';
import * as readline from 'node:readline';
import { startServer, request, lineToRequest, responseToLine } from './tests/lib.ts';

async function main(): Promise<number> {
  const argv = process.argv.slice(2);
  let server: string | undefined;
  let ledger: string | undefined;
  const pos: string[] = [];
  for (let i = 0; i < argv.length; i++) {
    if (argv[i] === '--server') server = argv[++i];
    else if (argv[i] === '--ledger') ledger = argv[++i];
    else pos.push(argv[i]);
  }
  if (pos.length !== 1) {
    process.stderr.write('usage: node adapter.ts <dir> [--server PATH] [--ledger PATH]\n');
    return 2;
  }
  const s = await startServer(pos[0], { server, ledger });
  const agent = new http.Agent({ keepAlive: true, maxSockets: 1 });
  const rl = readline.createInterface({ input: process.stdin, crlfDelay: Infinity });
  for await (const line of rl) {
    const req = lineToRequest(line);
    let answer: string;
    try {
      const r = await request(s.port, 'POST', req.path, req.body, agent);
      answer = responseToLine(req, r);
    } catch (e) {
      answer = `HTTP no response: ${(e as Error).message}`;
    }
    process.stdout.write(answer + '\n');
  }
  agent.destroy();
  s.proc.kill('SIGTERM');
  const { code, signal } = await s.exited;
  if (code !== 0) {
    process.stderr.write(`server exited ${signal ?? code}: ${s.stderr().trim()}\n`);
    return 1;
  }
  return 0;
}

main().then(
  (code) => process.exit(code),
  (e) => {
    process.stderr.write(`adapter: ${(e as Error).message}\n`);
    process.exit(1);
  },
);
