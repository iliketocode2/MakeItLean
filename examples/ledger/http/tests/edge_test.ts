// V5: the HTTP-only cases of http/REQUIREMENTS.md, which the model cannot see.
//
//   node examples/ledger/http/tests/edge_test.ts
//
// Body limit (413), malformed bodies and routes (H5, H6, H9), the `?` stand-in (H7, H8), startup
// (H1, H2: arguments, a corrupt directory, I/O errors, a busy port), shutdown (H3), fail-stop
// (H4: `ERR IO`, an unmappable answer, the ledger dying), and ordering across connections (H13).
// Failures the real ledger cannot be made to produce on demand (`ERR IO` mid-run, a garbage
// answer, a crash) are produced by small stub ledgers written by this test.

import * as fs from 'node:fs';
import * as http from 'node:http';
import * as net from 'node:net';
import * as path from 'node:path';
import { spawn, spawnSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { SERVER, LEDGER, startServer, request, tmpdir, check, summary } from './lib.ts';
import type { Resp, Running } from './lib.ts';

const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));
const is = (r: Resp, status: number, body: string) => r.status === status && r.body === body;
const show = (r: Resp) => `${r.status} ${r.body}`;
const post = (s: Running, p: string, body?: string | Buffer, headers?: Record<string, string>) =>
  request(s.port, 'POST', p, body, undefined, headers);

/** Run the server to completion (for startup failures): exit code, stdout, stderr. */
function runServer(args: string[]): { code: number | null; stdout: string; stderr: string } {
  const p = spawnSync(process.execPath, [SERVER, ...args], { encoding: 'utf8', timeout: 20000 });
  return { code: p.status, stdout: p.stdout, stderr: p.stderr };
}

function stub(dir: string, name: string, body: string): string {
  const p = path.join(dir, name);
  fs.writeFileSync(p, `#!/usr/bin/env bash\nread -r probe; echo "ERR USAGE"\n${body}\n`, { mode: 0o755 });
  return p;
}

async function stopped(s: Running, signal: NodeJS.Signals = 'SIGTERM') {
  s.proc.kill(signal);
  return s.exited;
}

async function main(): Promise<number> {
  const d = tmpdir();

  // --- Requests and responses on the real ledger ------------------------------------------
  {
    const s = await startServer(path.join(d, 'l1'));
    check(is(await post(s, '/open', '{"name":"alice"}'), 201, '{"ok":true}'), 'open alice');
    // H5: exact paths only; path before method.
    for (const p of ['/open/', '/open?x=1', '/Open', '/', '/accounts/x', '//open']) {
      const r = await post(s, p, '{"name":"alice"}');
      check(is(r, 404, '{"error":"NOT_FOUND"}'), `POST ${p}: ${show(r)}`);
    }
    check(is(await request(s.port, 'GET', '/nope'), 404, '{"error":"NOT_FOUND"}'), 'GET unknown path is 404');
    for (const m of ['GET', 'PUT', 'DELETE', 'PATCH']) {
      const r = await request(s.port, m, '/balance', '{"name":"alice"}');
      check(is(r, 405, '{"error":"METHOD_NOT_ALLOWED"}') && r.headers['allow'] === 'POST', `${m} /balance: ${show(r)}`);
    }
    // H6, H9: body size (65,536 allowed, 65,537 refused), checked before the JSON shape.
    const pad = (json: string, n: number) => json + ' '.repeat(n - json.length);
    check(is(await post(s, '/open', pad('{"name":"bob"}', 65536)), 201, '{"ok":true}'), '65,536-byte body accepted');
    check(is(await post(s, '/open', pad('{"name":"carol"}', 65537)), 413, '{"error":"TOO_LARGE"}'), '65,537-byte body is 413');
    check(is(await post(s, '/open', 'x'.repeat(70000)), 413, '{"error":"TOO_LARGE"}'), '413 before 400');
    {
      // chunked, no Content-Length
      const r = await new Promise<Resp>((resolve, reject) => {
        const req = http.request({ host: '127.0.0.1', port: s.port, method: 'POST', path: '/open', agent: false }, (res) => {
          let b = '';
          res.on('data', (c) => (b += c));
          res.on('end', () => resolve({ status: res.statusCode!, headers: res.headers, body: b }));
        });
        req.on('error', reject);
        for (let i = 0; i < 9; i++) req.write(' '.repeat(8000));
        req.end('{"name":"dave"}');
      });
      check(is(r, 413, '{"error":"TOO_LARGE"}'), `chunked 72,015-byte body: ${show(r)}`);
    }
    const r404 = await post(s, '/balance', '{"name":"carol"}');
    check(is(r404, 404, '{"error":"UNKNOWN_ACCOUNT","account":"carol"}'), `nothing was opened by a 413: ${show(r404)}`);
    // H9.4: malformed bodies.
    const usage: [string, string | Buffer][] = [
      ['/balance', '[]'], ['/balance', 'null'], ['/balance', '"alice"'], ['/balance', '7'],
      ['/balance', '{"name":null}'], ['/balance', '{"name":["alice"]}'], ['/balance', '{}'],
      ['/balance', '{"name":"alice","__proto__":"x"}'], ['/balance', '{"Name":"alice"}'],
      ['/balance', ' '], ['/balance', '{"name":"alice"} x'], ['/balance', Buffer.from([0x7b, 0xff, 0x7d])],
      ['/balance', Buffer.from('﻿{"name":"alice"}', 'utf8')], ['/open', ''],
      ['/deposit', '{"name":"alice","amount":5}'], ['/deposit', '{"name":"alice","amount":"5","x":"1"}'],
      ['/transfer', '{"from":"alice","to":"bob"}'], ['/accounts', '{"x":1}'], ['/total', '[]'],
    ];
    for (const [p, b] of usage) {
      const r = await post(s, p, b);
      check(is(r, 400, '{"error":"USAGE"}'), `${p} ${JSON.stringify(b.toString())}: ${show(r)}`);
    }
    // H6: an empty body is {}; Content-Type is not checked; the last duplicate key counts.
    check(is(await post(s, '/total'), 200, '{"total":"0"}'), 'empty body on /total');
    check(is(await post(s, '/accounts', '  {}  ', { 'Content-Type': 'text/plain' }), 200,
      '{"accounts":[{"name":"alice","balance":"0"},{"name":"bob","balance":"0"}]}'), 'any Content-Type');
    check(is(await post(s, '/deposit', '{"name":"zz","amount":"5","name":"alice"}'), 200, '{"balance":"5"}'), 'last duplicate key counts');
    // H7, H8: strings that cannot be one word are sent as `?`; no protocol injection.
    for (const n of ['a\nopen evil', 'a b', '', 'tab\there', 'cr\r', 'del\u007f', '\u0000']) {
      const r = await post(s, '/open', JSON.stringify({ name: n }));
      check(is(r, 422, '{"error":"BAD_NAME"}'), `open ${JSON.stringify(n)}: ${show(r)}`);
    }
    for (const n of ['é', '?', 'x'.repeat(65), 'a/b', 'evil x']) {
      const r = await post(s, '/open', JSON.stringify({ name: n }));
      check(is(r, 422, '{"error":"BAD_NAME"}'), `open ${JSON.stringify(n)}: ${show(r)}`);
    }
    for (const a of ['5\n', ' 5', '', '5 ', '1\ndeposit alice 9', '٥', '5.0', '-5', '+5', '1e3', '0x10']) {
      const r = await post(s, '/deposit', JSON.stringify({ name: 'alice', amount: a }));
      check(is(r, 400, '{"error":"USAGE"}'), `deposit amount ${JSON.stringify(a)}: ${show(r)}`);
    }
    const mixed = await post(s, '/deposit', JSON.stringify({ name: 'a b', amount: 'x' }));
    check(is(mixed, 400, '{"error":"USAGE"}'), `bad name and bad amount is USAGE: ${show(mixed)}`);
    check(is(await post(s, '/deposit', '{"name":"alice","amount":"007"}'), 200, '{"balance":"12"}'), 'leading zeros are digits');
    const acc = await post(s, '/accounts');
    check(is(acc, 200, '{"accounts":[{"name":"alice","balance":"12"},{"name":"bob","balance":"0"}]}'),
      `no account was created by a stand-in or an injection: ${show(acc)}`);
    // Keep-alive: several requests on one connection.
    const agent = new http.Agent({ keepAlive: true, maxSockets: 1 });
    for (let i = 0; i < 3; i++) {
      const r = await request(s.port, 'POST', '/balance', '{"name":"alice"}', agent);
      check(is(r, 200, '{"balance":"12"}'), `keep-alive request ${i}: ${show(r)}`);
    }
    agent.destroy();
    // H13: concurrent requests from many connections run one at a time.
    const rs = await Promise.all(Array.from({ length: 40 }, () => post(s, '/deposit', '{"name":"bob","amount":"1"}')));
    const seen = rs.map((r) => JSON.parse(r.body).balance).sort((x: string, y: string) => Number(x) - Number(y));
    check(JSON.stringify(seen) === JSON.stringify(Array.from({ length: 40 }, (_, i) => String(i + 1))),
      `40 concurrent deposits see balances 1..40: ${seen}`);
    // H3: SIGINT stops the server with exit 0; the data survives a restart.
    const e = await stopped(s, 'SIGINT');
    check(e.code === 0, `SIGINT exit ${e.signal ?? e.code}`);
    const s2 = await startServer(path.join(d, 'l1'));
    check(is(await post(s2, '/balance', '{"name":"bob"}'), 200, '{"balance":"40"}'), 'data survives a restart');
    // H15 is trusted; H1: a second server on the same port cannot listen (exit 4).
    const busy = runServer([path.join(d, 'l-other'), '--port', String(s2.port)]);
    check(busy.code === 4 && /cannot listen/.test(busy.stderr) && busy.stdout === '', `busy port: exit ${busy.code} ${busy.stderr}`);
    const e2 = await stopped(s2);
    check(e2.code === 0, `SIGTERM exit ${e2.signal ?? e2.code}`);
    const refused = await new Promise<boolean>((res) => {
      const c = net.connect(s2.port, '127.0.0.1');
      c.on('connect', () => { c.destroy(); res(false); });
      c.on('error', () => res(true));
    });
    check(refused, 'no connection accepted after shutdown');
  }

  // --- Startup (H1, H2) ------------------------------------------------------------------
  {
    for (const args of [[], ['a', 'b'], ['a', '--port'], ['a', '--port', 'x'], ['a', '--port', '70000'],
                        ['a', '--bogus'], ['a', '--port=1'], ['--host', '127.0.0.1']]) {
      const r = runServer(args);
      check(r.code === 2 && r.stderr.startsWith('usage:') && r.stdout === '', `args ${JSON.stringify(args)}: exit ${r.code}`);
    }
    // A corrupt directory: exit 3 with the ledger's line on stderr, no file changed.
    const L = path.join(d, 'corrupt');
    spawnSync(LEDGER, [L, 'open', 'a']);
    spawnSync(LEDGER, [L, 'deposit', 'a', '5']);
    const f = path.join(L, 'leankv.log');
    const b = fs.readFileSync(f);
    b[Math.floor(b.length / 4)] ^= 0xff;
    fs.writeFileSync(f, b);
    const hash = () => createHash('sha256').update(fs.readFileSync(f)).digest('hex');
    const before = hash();
    const r = runServer([L, '--port', '0']);
    check(r.code === 3 && /^ERR CORRUPT offset \d+\n$/.test(r.stderr) && r.stdout === '',
      `corrupt dir: exit ${r.code}, stderr ${JSON.stringify(r.stderr)}`);
    check(hash() === before, 'corrupt dir: file unchanged');
    // The store cannot be opened: exit 4.
    const io = runServer(['/proc/ledger-cannot-exist', '--port', '0']);
    check(io.code === 4 && io.stderr.startsWith('ERR IO') && io.stdout === '', `I/O error at startup: exit ${io.code} ${io.stderr}`);
    const nobin = runServer([path.join(d, 'l3'), '--port', '0', '--ledger', path.join(d, 'no-such-ledger')]);
    check(nobin.code === 4 && nobin.stdout === '', `missing ledger binary: exit ${nobin.code}`);
  }

  // --- Fail-stop and shutdown with stub ledgers (H3, H4) -----------------------------------
  const three = async (s: Running): Promise<Resp[]> => {
    const first = post(s, '/total');
    await sleep(100); // the first is in flight; the next two wait in the queue
    const rest = [post(s, '/total'), post(s, '/total')];
    await sleep(100);
    return Promise.all([first, ...rest]);
  };
  const UNAV = '{"error":"UNAVAILABLE"}';
  {
    const s = await startServer(path.join(d, 's1'), { ledger: stub(d, 'io.sh', 'read -r line; sleep 0.4; echo "ERR IO"; exit 4') });
    const [a, b, c] = await three(s);
    const e = await s.exited;
    check(is(a, 500, '{"error":"IO"}') && is(b, 503, UNAV) && is(c, 503, UNAV) && e.code === 4,
      `ERR IO: ${show(a)} / ${show(b)} / ${show(c)}, exit ${e.code}`);
  }
  {
    const s = await startServer(path.join(d, 's2'), { ledger: stub(d, 'garbage.sh', 'read -r line; sleep 0.4; echo "TOTAL 12x"; cat'), });
    const [a, b, c] = await three(s);
    const e = await s.exited;
    check(is(a, 500, '{"error":"INTERNAL"}') && is(b, 503, UNAV) && is(c, 503, UNAV) && e.code === 5,
      `unmappable answer: ${show(a)} / ${show(b)} / ${show(c)}, exit ${e.code}`);
  }
  {
    const s = await startServer(path.join(d, 's3'), { ledger: stub(d, 'die.sh', 'read -r line; sleep 0.4; exit 1') });
    const [a, b, c] = await three(s);
    const e = await s.exited;
    check(is(a, 500, '{"error":"INTERNAL"}') && is(b, 503, UNAV) && is(c, 503, UNAV) && e.code === 5,
      `ledger dies: ${show(a)} / ${show(b)} / ${show(c)}, exit ${e.code}`);
  }
  {
    const mark = path.join(d, 'eof.mark');
    const s = await startServer(path.join(d, 's4'), {
      ledger: stub(d, 'slow.sh', `while read -r line; do sleep 0.4; echo "TOTAL 0"; done\ntouch '${mark}'`),
    });
    const first = post(s, '/total');
    await sleep(100);
    const rest = [post(s, '/total'), post(s, '/total')];
    await sleep(100);
    s.proc.kill('SIGTERM');
    const [a, b, c] = await Promise.all([first, ...rest]);
    const e = await s.exited;
    check(is(a, 200, '{"total":"0"}') && is(b, 503, UNAV) && is(c, 503, UNAV) && e.code === 0,
      `SIGTERM with one in flight and two waiting: ${show(a)} / ${show(b)} / ${show(c)}, exit ${e.code}`);
    await sleep(200);
    check(fs.existsSync(mark), 'shutdown closes the ledger input (serve reaches end of input)');
  }

  fs.rmSync(d, { recursive: true, force: true });
  return summary('edge_test');
}

main().then((c) => process.exit(c), (e) => { console.log(`edge_test: ERROR ${e.stack}`); process.exit(1); });
