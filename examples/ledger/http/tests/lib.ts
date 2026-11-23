// Test helpers for the Ledger HTTP API: start a server, send requests, and translate between
// protocol lines and HTTP exchanges (http/REQUIREMENTS.md V2). Used by adapter.ts and the tests.
//
// The tables here are written from http/REQUIREMENTS.md independently of server.ts, so a
// mapping bug in the server shows up as a disagreement with the oracle. (A bug mirrored in both
// would not; the literal replay, V4, covers that.) Node.js standard library only.

import * as http from 'node:http';
import { spawn } from 'node:child_process';
import type { ChildProcess } from 'node:child_process';
import * as path from 'node:path';
import * as fs from 'node:fs';
import { fileURLToPath } from 'node:url';

export const HTTP_DIR = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
export const SERVER = path.join(HTTP_DIR, 'server.ts');
export const BIN = path.resolve(HTTP_DIR, '..', 'impl', '.lake', 'build', 'bin');
export const LEDGER = path.join(BIN, 'ledger');
export const ORACLE = path.join(BIN, 'ledger-oracle');

// H5: route of each command and the body fields, in the order of the command's words.
export const FIELDS: Record<string, string[]> = {
  open: ['name'],
  deposit: ['name', 'amount'],
  withdraw: ['name', 'amount'],
  transfer: ['from', 'to', 'amount'],
  balance: ['name'],
  accounts: [],
  total: [],
};

// H10: the status of each error code.
const ERROR_STATUS: Record<string, number> = {
  BAD_NAME: 422,
  BAD_AMOUNT: 422,
  SAME_ACCOUNT: 422,
  UNKNOWN_ACCOUNT: 404,
  ACCOUNT_EXISTS: 409,
  INSUFFICIENT_FUNDS: 409,
  BALANCE_LIMIT: 409,
  USAGE: 400,
  IO: 500,
};

export type Running = {
  proc: ChildProcess;
  port: number;
  stderr: () => string;
  exited: Promise<{ code: number | null; signal: NodeJS.Signals | null }>;
};

/** Start `server.ts <dir> --port 0` (or another server file) and wait for its listening line. */
export function startServer(
  dir: string,
  opts: { server?: string; ledger?: string; extra?: string[] } = {},
): Promise<Running> {
  const args = [opts.server ?? SERVER, dir, '--port', '0'];
  if (opts.ledger !== undefined) args.push('--ledger', opts.ledger);
  args.push(...(opts.extra ?? []));
  const proc = spawn(process.execPath, args, { stdio: ['ignore', 'pipe', 'pipe'] });
  let err = '';
  proc.stderr!.on('data', (c) => (err += c));
  const exited = new Promise<{ code: number | null; signal: NodeJS.Signals | null }>((res) =>
    proc.on('exit', (code, signal) => res({ code, signal })),
  );
  return new Promise((resolve, reject) => {
    let out = '';
    proc.stdout!.setEncoding('utf8');
    proc.stdout!.on('data', (c: string) => {
      out += c;
      const m = /^listening on http:\/\/[^\n]*:(\d+)\n/.exec(out);
      if (m) resolve({ proc, port: Number(m[1]), stderr: () => err, exited });
    });
    exited.then(({ code, signal }) =>
      reject(new Error(`server exited before listening (${signal ?? code}): ${err.trim()}`)),
    );
  });
}

export type Resp = { status: number; headers: http.IncomingHttpHeaders; body: string };

/** One HTTP request; resolves with the status, headers and body text. */
export function request(
  port: number,
  method: string,
  urlPath: string,
  body?: string | Buffer,
  agent?: http.Agent,
  headers: Record<string, string> = {},
): Promise<Resp> {
  return new Promise((resolve, reject) => {
    const req = http.request(
      { host: '127.0.0.1', port, method, path: urlPath, agent: agent ?? false, headers },
      (res) => {
        const chunks: Buffer[] = [];
        res.on('data', (c: Buffer) => chunks.push(c));
        res.on('end', () =>
          resolve({ status: res.statusCode!, headers: res.headers, body: Buffer.concat(chunks).toString('utf8') }),
        );
        res.on('error', reject);
      },
    );
    req.on('error', reject);
    if (body !== undefined) req.end(body);
    else req.end();
  });
}

/** The HTTP request for one protocol line (the inverse direction of H5–H8). Words are mapped to
 * the route's fields in order, each as a JSON string with the same text. Missing words leave a
 * field out and extra words become extra fields, so a wrong word count is a malformed body
 * (400 USAGE, H9.4). An unknown command word becomes a request to the path of that word, which
 * the server answers 404 NOT_FOUND; the adapter reads that back as `ERR USAGE`, the line
 * protocol's answer to an unknown command. */
export function lineToRequest(line: string): { cmd: string; known: boolean; path: string; body: string } {
  const w = line.split(' ').filter((x) => x.length > 0);
  const cmd = w[0] ?? '';
  if (!Object.prototype.hasOwnProperty.call(FIELDS, cmd)) {
    return { cmd, known: false, path: '/' + encodeURIComponent(cmd), body: '{}' };
  }
  const fields = FIELDS[cmd];
  const obj: Record<string, string> = {};
  const args = w.slice(1);
  args.forEach((a, i) => (obj[i < fields.length ? fields[i] : `extra${i - fields.length + 1}`] = a));
  return { cmd, known: true, path: '/' + cmd, body: JSON.stringify(obj) };
}

function digits(x: unknown): x is string {
  return typeof x === 'string' && /^[0-9]+$/.test(x);
}

/** The answer line a response stands for (the inverse of H10), or a line starting with `HTTP`
 * that no oracle answer equals, when the response is not one H10 allows for this request. */
export function responseToLine(req: { cmd: string; known: boolean }, r: Resp): string {
  const bad = `HTTP ${r.status} ${r.body}`;
  if (r.headers['content-type'] !== 'application/json') return bad + ' (content-type)';
  if (r.headers['content-length'] !== String(Buffer.byteLength(r.body))) return bad + ' (content-length)';
  let v: any;
  try {
    v = JSON.parse(r.body);
  } catch {
    return bad;
  }
  // H12: compact JSON, keys in the order shown. Re-serialising must give the same text.
  if (JSON.stringify(v) !== r.body || typeof v !== 'object' || v === null) return bad + ' (format)';
  const keys = Object.keys(v).join(',');
  if (!req.known) {
    return r.status === 404 && keys === 'error' && v.error === 'NOT_FOUND' ? 'ERR USAGE' : bad;
  }
  if (keys === 'ok' && v.ok === true) {
    if (req.cmd === 'open' && r.status === 201) return 'OK';
    if (req.cmd === 'transfer' && r.status === 200) return 'OK';
    return bad;
  }
  if (keys === 'balance' && r.status === 200 && digits(v.balance)) return `BALANCE ${v.balance}`;
  if (keys === 'total' && r.status === 200 && digits(v.total)) return `TOTAL ${v.total}`;
  if (keys === 'accounts' && r.status === 200 && Array.isArray(v.accounts)) {
    const parts = [`ACCOUNTS ${v.accounts.length}`];
    for (const a of v.accounts) {
      if (typeof a !== 'object' || a === null || Object.keys(a).join(',') !== 'name,balance') return bad;
      if (typeof a.name !== 'string' || !digits(a.balance)) return bad;
      parts.push(`${a.name} ${a.balance}`);
    }
    return parts.join(' ');
  }
  if (keys === 'error,account' && v.error === 'UNKNOWN_ACCOUNT' && r.status === 404 && typeof v.account === 'string') {
    return `ERR UNKNOWN_ACCOUNT ${v.account}`;
  }
  if (keys === 'error' && typeof v.error === 'string' && v.error !== 'UNKNOWN_ACCOUNT' &&
      ERROR_STATUS[v.error] === r.status) {
    return `ERR ${v.error}`;
  }
  return bad;
}

/** Answer lines of the oracle (the frozen model) for a sequence of protocol lines. */
export function oracle(lines: string[]): Promise<string[]> {
  return new Promise((resolve, reject) => {
    const p = spawn(ORACLE, [], { stdio: ['pipe', 'pipe', 'inherit'] });
    let out = '';
    p.stdout!.setEncoding('utf8');
    p.stdout!.on('data', (c: string) => (out += c));
    p.on('error', reject);
    p.on('exit', (code) => {
      if (code !== 0) return reject(new Error(`oracle exited ${code}`));
      resolve(out.split('\n').slice(0, -1));
    });
    p.stdin!.end(lines.map((l) => l + '\n').join(''));
  });
}

/** A fresh temporary directory. */
export function tmpdir(prefix = 'ledger-http-'): string {
  return fs.mkdtempSync(path.join(process.env.TMPDIR ?? '/tmp', prefix));
}

/** A seeded pseudo-random generator (mulberry32), so test runs are reproducible. */
export function rng(seed: number): () => number {
  let a = seed >>> 0;
  return () => {
    a = (a + 0x6d2b79f5) >>> 0;
    let t = a;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

let failures = 0;
let passes = 0;
/** Record one check. */
export function check(ok: boolean, what: string): void {
  if (ok) passes++;
  else {
    failures++;
    console.log(`FAIL: ${what}`);
  }
}
export function summary(name: string): number {
  console.log(`${name}: ${passes} passed, ${failures} failed`);
  return failures === 0 ? 0 : 1;
}
