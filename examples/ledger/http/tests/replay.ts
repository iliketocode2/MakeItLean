// V4: replay the literal examples E1–E35 of http/REQUIREMENTS.md byte for byte.
//
//   node examples/ledger/http/tests/replay.ts
//
// The examples are read from the requirements document itself, so the test checks what the user
// approved. Each request is sent verbatim (CRLF line endings, the Host port replaced by the test
// server's port) on a fresh server and a new, empty directory, in order, one connection each.
// For each response the test requires the exact status line, the exact Content-Type,
// Content-Length and Allow headers of the example, no other header except Date, Connection and
// Keep-Alive (H12), and the exact body.
//
// The ledger is run through a wrapper that records every line the server sends it, so the test
// also checks each example's "Protocol line" (including the `?` stand-in, H7, H8) and that
// examples "answered by the server alone" send nothing. Finally the documented protocol lines
// are run through `ledger-oracle` (the frozen model) and must give the documented answers.

import * as fs from 'node:fs';
import * as net from 'node:net';
import * as path from 'node:path';
import { HTTP_DIR, LEDGER, startServer, tmpdir, oracle, check, summary } from './lib.ts';

type Example = {
  id: string;
  line: string | null; // the protocol line sent to the ledger, or null (server alone)
  answer: string | null; // the ledger's answer line
  request: string; // CRLF wire form, Host port still 8080
  status: string;
  headers: [string, string][];
  body: string;
};

function parseDoc(): Example[] {
  const doc = fs.readFileSync(path.join(HTTP_DIR, 'REQUIREMENTS.md'), 'utf8');
  const re = /\*\*E(\d+)\*\*([^\n]*)\n\n```http\n([\s\S]*?)```\n```http\n([\s\S]*?)```/g;
  const out: Example[] = [];
  for (const m of doc.matchAll(re)) {
    const pl = /Protocol line `([^`]*)` → `([^`]*)`/.exec(m[2]);
    const alone = /Answered by the server alone/.test(m[2]);
    if (!pl && !alone) throw new Error(`E${m[1]}: no protocol line and not server-alone`);
    // A block is "head\n\nbody\n"; the body has no newline of its own (H12).
    const split = (block: string): [string[], string] => {
      const i = block.indexOf('\n\n');
      if (i < 0) throw new Error(`E${m[1]}: no blank line`);
      const body = block.slice(i + 2);
      return [block.slice(0, i).split('\n'), body.endsWith('\n') ? body.slice(0, -1) : body];
    };
    const [rqHead, rqBody] = split(m[3]);
    const [rsHead, rsBody] = split(m[4]);
    const declared = rqHead.find((h) => h.startsWith('Content-Length: '));
    if (declared && Number(declared.slice(16)) !== Buffer.byteLength(rqBody)) {
      throw new Error(`E${m[1]}: request Content-Length does not match its body`);
    }
    out.push({
      id: `E${m[1]}`,
      line: pl ? pl[1] : null,
      answer: pl ? pl[2] : null,
      request: rqHead.join('\r\n') + '\r\n\r\n' + rqBody,
      status: rsHead[0],
      headers: rsHead.slice(1).map((h) => {
        const k = h.indexOf(': ');
        return [h.slice(0, k), h.slice(k + 2)] as [string, string];
      }),
      body: rsBody,
    });
  }
  return out;
}

/** Send raw bytes on a new connection; read one response (headers and Content-Length body). */
function exchange(port: number, raw: string): Promise<{ head: string[]; body: string }> {
  return new Promise((resolve, reject) => {
    const sock = net.connect(port, '127.0.0.1');
    let buf = Buffer.alloc(0);
    const timer = setTimeout(() => {
      sock.destroy();
      reject(new Error('timeout'));
    }, 10000);
    sock.on('data', (c: Buffer) => {
      buf = Buffer.concat([buf, c]);
      const i = buf.indexOf('\r\n\r\n');
      if (i < 0) return;
      const head = buf.subarray(0, i).toString('latin1').split('\r\n');
      const cl = head.find((h) => /^content-length:/i.test(h));
      const len = cl ? Number(cl.split(':')[1].trim()) : 0;
      if (buf.length - (i + 4) < len) return;
      clearTimeout(timer);
      sock.destroy();
      resolve({ head, body: buf.subarray(i + 4, i + 4 + len).toString('utf8') });
    });
    sock.on('error', (e) => {
      clearTimeout(timer);
      reject(e);
    });
    sock.write(Buffer.from(raw, 'utf8'));
  });
}

async function main(): Promise<number> {
  const examples = parseDoc();
  check(examples.length === 35, `found ${examples.length} examples, want 35`);
  const d = tmpdir();
  const log = path.join(d, 'sent.log');
  const wrapper = path.join(d, 'ledger-tee.sh');
  fs.writeFileSync(log, '');
  fs.writeFileSync(wrapper, `#!/usr/bin/env bash\ntee -a '${log}' | '${LEDGER}' "$@"\n`, { mode: 0o755 });
  const s = await startServer(path.join(d, 'ledger'), { ledger: wrapper });
  const sentCount = () => fs.readFileSync(log, 'utf8').split('\n').length - 1;
  try {
    for (const ex of examples) {
      const before = sentCount();
      const raw = ex.request.replace(/^Host: 127\.0\.0\.1:8080\r$/m, `Host: 127.0.0.1:${s.port}\r`);
      check(raw !== ex.request, `${ex.id}: Host header not found`);
      const r = await exchange(s.port, raw);
      check(r.head[0] === ex.status, `${ex.id}: status '${r.head[0]}', want '${ex.status}'`);
      const got = new Map<string, string>();
      for (const h of r.head.slice(1)) {
        const k = h.indexOf(':');
        got.set(h.slice(0, k).toLowerCase(), h.slice(k + 1).trim());
      }
      for (const [k, v] of ex.headers) {
        check(got.get(k.toLowerCase()) === v, `${ex.id}: header ${k} '${got.get(k.toLowerCase())}', want '${v}'`);
      }
      const allowed = new Set([...ex.headers.map(([k]) => k.toLowerCase()), 'date', 'connection', 'keep-alive']);
      for (const k of got.keys()) check(allowed.has(k), `${ex.id}: unexpected header ${k}`);
      check(r.body === ex.body, `${ex.id}: body '${r.body}', want '${ex.body}'`);
      const sent = fs.readFileSync(log, 'utf8').split('\n').slice(before, -1);
      const want = ex.line === null ? [] : [ex.line];
      check(JSON.stringify(sent) === JSON.stringify(want),
        `${ex.id}: sent to ledger ${JSON.stringify(sent)}, want ${JSON.stringify(want)}`);
    }
  } finally {
    s.proc.kill('SIGTERM');
    const e = await s.exited;
    check(e.code === 0, `server exit ${e.signal ?? e.code} after SIGTERM, want 0`);
  }
  // The documented protocol lines and answers agree with the frozen model.
  const withLine = examples.filter((e) => e.line !== null);
  const answers = await oracle(withLine.map((e) => e.line!));
  withLine.forEach((e, i) =>
    check(answers[i] === e.answer, `${e.id}: oracle answers '${answers[i]}', document says '${e.answer}'`),
  );
  fs.rmSync(d, { recursive: true, force: true });
  console.log(`replay: ${examples.length} literal examples replayed byte for byte`);
  return summary('replay');
}

main().then((c) => process.exit(c), (e) => { console.log(`replay: ERROR ${e.stack}`); process.exit(1); });
