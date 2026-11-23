// Ledger HTTP JSON API (REQUIREMENTS.md R20; http/REQUIREMENTS.md H1–H16).
//
//   node examples/ledger/http/server.ts <dir> [--port N] [--host ADDR] [--ledger PATH]
//
// TRANSPORT ONLY. The server turns each request into one line of Ledger's line protocol (R18),
// writes it to one long-lived `ledger <dir> serve` process, reads the one answer line, and turns
// that line into the HTTP response (H10). Every ledger rule (names, amounts, balances, the check
// order, durability) is decided by the Lean ledger. The server itself decides only the route, the
// method, the body size and the JSON shape of the body (H9). Trusted, not verified; tested
// against the Lean reference model (http/REQUIREMENTS.md §8).
//
// Node.js standard library only (H1, V8). Runs directly with Node 24's type stripping.

import * as http from 'node:http';
import { spawn } from 'node:child_process';
import type { ChildProcess } from 'node:child_process';
import * as path from 'node:path';
import { fileURLToPath } from 'node:url';

const MAX_BODY = 65536; // H6

// H5: one POST route per Ledger command; the body's fields, in the order of the command's words.
const ROUTES: Record<string, { cmd: string; fields: string[] }> = {
  '/open': { cmd: 'open', fields: ['name'] },
  '/deposit': { cmd: 'deposit', fields: ['name', 'amount'] },
  '/withdraw': { cmd: 'withdraw', fields: ['name', 'amount'] },
  '/transfer': { cmd: 'transfer', fields: ['from', 'to', 'amount'] },
  '/balance': { cmd: 'balance', fields: ['name'] },
  '/accounts': { cmd: 'accounts', fields: [] },
  '/total': { cmd: 'total', fields: [] },
};

// ---------------------------------------------------------------------------------------------
// Request body to protocol line (H6–H9)

type Reply = { status: number; body: unknown; headers?: Record<string, string>; fatal?: number };

const USAGE: Reply = { status: 400, body: { error: 'USAGE' } };

/** One word of a protocol line: the string itself when it can be written as one word (not
 * empty, no space, no control character U+0000–U+001F or U+007F); otherwise the stand-in `?`
 * (H7, H8, H-D4). The ledger then answers exactly as the model does for the original string. */
export function word(s: string): string {
  return s.length > 0 && !/[\u0000-\u001f\u007f ]/.test(s) ? s : '?';
}

/** The protocol line for a request body, or a 400 USAGE reply when the body is not a JSON object
 * whose keys are exactly the route's fields, each a JSON string (H6, H9.4). */
export function bodyToLine(route: { cmd: string; fields: string[] }, raw: Buffer): string | Reply {
  let text: string;
  try {
    // Invalid UTF-8 is not JSON text; a byte-order mark is kept, so JSON.parse rejects it.
    text = new TextDecoder('utf-8', { fatal: true, ignoreBOM: true }).decode(raw);
  } catch {
    return USAGE;
  }
  let v: unknown;
  if (text.length === 0) v = {}; // H6: an empty body counts as {}
  else {
    try {
      v = JSON.parse(text);
    } catch {
      return USAGE;
    }
  }
  if (typeof v !== 'object' || v === null || Array.isArray(v)) return USAGE;
  const obj = v as Record<string, unknown>;
  const keys = Object.keys(obj);
  if (keys.length !== route.fields.length) return USAGE;
  for (const f of route.fields) {
    if (!Object.prototype.hasOwnProperty.call(obj, f) || typeof obj[f] !== 'string') return USAGE;
  }
  return [route.cmd, ...route.fields.map((f) => word(obj[f] as string))].join(' ');
}

// ---------------------------------------------------------------------------------------------
// Answer line to response (H10, H11, H16)

const DIGITS = /^[0-9]+$/;
const ERRORS: Record<string, number> = {
  BAD_NAME: 422,
  BAD_AMOUNT: 422,
  SAME_ACCOUNT: 422,
  ACCOUNT_EXISTS: 409,
  INSUFFICIENT_FUNDS: 409,
  BALANCE_LIMIT: 409,
  USAGE: 400,
};
const INTERNAL: Reply = { status: 500, body: { error: 'INTERNAL' }, fatal: 5 };

/** The response for the ledger's answer line to a command `cmd` (H10). Numbers are copied as
 * text, never converted (H11). A line that is not in the table is 500 INTERNAL (fail-stop). */
export function answerToReply(line: string, cmd: string): Reply {
  if (line === 'OK') {
    if (cmd === 'open') return { status: 201, body: { ok: true } };
    if (cmd === 'transfer') return { status: 200, body: { ok: true } };
    return INTERNAL;
  }
  if (line === 'ERR IO') return { status: 500, body: { error: 'IO' }, fatal: 4 };
  const w = line.split(' ');
  switch (w[0]) {
    case 'BALANCE':
      return w.length === 2 && DIGITS.test(w[1]) ? { status: 200, body: { balance: w[1] } } : INTERNAL;
    case 'TOTAL':
      return w.length === 2 && DIGITS.test(w[1]) ? { status: 200, body: { total: w[1] } } : INTERNAL;
    case 'ACCOUNTS': {
      if (w.length < 2 || !DIGITS.test(w[1]) || w.length !== 2 + 2 * Number(w[1])) return INTERNAL;
      const accounts: { name: string; balance: string }[] = [];
      for (let i = 2; i < w.length; i += 2) {
        if (w[i].length === 0 || !DIGITS.test(w[i + 1])) return INTERNAL;
        accounts.push({ name: w[i], balance: w[i + 1] });
      }
      return { status: 200, body: { accounts } };
    }
    case 'ERR':
      if (w.length === 3 && w[1] === 'UNKNOWN_ACCOUNT' && w[2].length > 0) {
        return { status: 404, body: { error: 'UNKNOWN_ACCOUNT', account: w[2] } };
      }
      if (w.length === 2 && Object.prototype.hasOwnProperty.call(ERRORS, w[1])) {
        return { status: ERRORS[w[1]], body: { error: w[1] } };
      }
      return INTERNAL;
    default:
      return INTERNAL;
  }
}

/** Send a compact JSON response with Content-Type and Content-Length (H12). */
function send(res: http.ServerResponse, r: Reply): void {
  if (res.headersSent || res.destroyed) return;
  const body = Buffer.from(JSON.stringify(r.body), 'utf8');
  res.writeHead(r.status, {
    ...(r.headers ?? {}),
    'Content-Type': 'application/json',
    'Content-Length': String(body.length),
  });
  res.end(body);
}

// ---------------------------------------------------------------------------------------------
// Command line (H1)

type Args = { dir: string; port: number; host: string; ledger: string };

const USAGE_TEXT =
  'usage: node server.ts <dir> [--port N] [--host ADDR] [--ledger PATH]';

function parseArgs(argv: string[]): Args | null {
  const here = path.dirname(fileURLToPath(import.meta.url));
  const a: Args = {
    dir: '',
    port: 8080,
    host: '127.0.0.1',
    ledger: path.resolve(here, '..', 'impl', '.lake', 'build', 'bin', 'ledger'),
  };
  const pos: string[] = [];
  for (let i = 0; i < argv.length; i++) {
    const x = argv[i];
    if (x === '--port' || x === '--host' || x === '--ledger') {
      const v = argv[++i];
      if (v === undefined) return null;
      if (x === '--port') {
        if (!DIGITS.test(v) || Number(v) > 65535) return null;
        a.port = Number(v);
      } else if (x === '--host') {
        if (v.length === 0) return null;
        a.host = v;
      } else a.ledger = v;
    } else if (x.startsWith('--')) return null;
    else pos.push(x);
  }
  if (pos.length !== 1 || pos[0].length === 0) return null;
  a.dir = pos[0];
  return a;
}

// ---------------------------------------------------------------------------------------------
// The server: one ledger process, one command at a time, in arrival order (H13)

type Job = { line: string; cmd: string; res: http.ServerResponse };

function main(): void {
  const args = parseArgs(process.argv.slice(2));
  if (args === null) {
    process.stderr.write(USAGE_TEXT + '\n');
    process.exit(2);
  }

  let state: 'starting' | 'running' | 'stopping' | 'failed' = 'starting';
  const queue: Job[] = []; // waiting, not yet sent to the ledger
  let busy: Job | null = null; // sent, answer not yet back
  let openResponses = 0;
  let exitCode: number | null = null;

  // Exit once every response already made has been handed to the operating system.
  const exitWhenFlushed = (code: number): void => {
    exitCode = code;
    if (openResponses === 0) process.exit(code);
    setTimeout(() => process.exit(code), 2000).unref();
  };

  const ledger: ChildProcess = spawn(args.ledger, [args.dir, 'serve'], {
    stdio: ['pipe', 'pipe', 'inherit'],
  });
  let ledgerExited = false;
  ledger.stdin!.on('error', () => {}); // EPIPE when the ledger stopped (handled by 'exit')

  const server = http.createServer((req, res) => {
    openResponses++;
    res.on('close', () => {
      openResponses--;
      if (exitCode !== null && openResponses === 0) process.exit(exitCode);
    });
    req.on('error', () => {});
    handle(req, res);
  });

  const unavailable = (job: Job): void => send(job.res, { status: 503, body: { error: 'UNAVAILABLE' } });

  // H4: fail-stop. The request in flight already has its 500; every waiting one gets 503.
  const fail = (code: number): void => {
    if (state === 'failed') return;
    state = 'failed';
    server.close();
    for (const j of queue.splice(0)) unavailable(j);
    if (!ledgerExited) ledger.stdin!.end();
    exitWhenFlushed(code);
  };

  // H3: shutdown once nothing is in flight: close the ledger's input; serve then exits 0.
  const finishStop = (): void => {
    if (busy !== null) return;
    if (!ledgerExited) ledger.stdin!.end();
    else exitWhenFlushed(0);
  };

  const dispatch = (): void => {
    if (state !== 'running' || busy !== null || queue.length === 0) return;
    busy = queue.shift()!;
    ledger.stdin!.write(busy.line + '\n');
  };

  // One answer line from the ledger.
  const onLine = (line: string): void => {
    if (state === 'starting') {
      // The startup probe (an empty line, answered `ERR USAGE` without touching the store)
      // proves the store is open; or the ledger reports why it could not open it (H2).
      if (line === 'ERR USAGE') return listen();
      process.stderr.write(line + '\n');
      state = 'failed';
      ledger.stdin!.end();
      process.exit(line.startsWith('ERR CORRUPT') ? 3 : line.startsWith('ERR IO') ? 4 : 5);
    }
    const job = busy;
    busy = null;
    if (job === null) return fail(5); // an answer nobody asked for
    const r = answerToReply(line, job.cmd);
    send(job.res, r);
    if (r.fatal !== undefined) return fail(r.fatal);
    if (state === 'stopping') return finishStop();
    dispatch();
  };

  let pending = '';
  ledger.stdout!.setEncoding('utf8');
  ledger.stdout!.on('data', (chunk: string) => {
    pending += chunk;
    let i: number;
    while ((i = pending.indexOf('\n')) >= 0) {
      const line = pending.slice(0, i);
      pending = pending.slice(i + 1);
      onLine(line);
    }
  });

  ledger.on('error', (e) => {
    // The ledger could not be started at all (for example, no such file).
    if (state === 'starting') {
      process.stderr.write(`cannot start ledger ${args.ledger}: ${e.message}\n`);
      process.exit(4);
    }
  });
  ledger.on('exit', (code, signal) => {
    ledgerExited = true;
    if (state === 'starting') {
      process.stderr.write(`ledger exited during startup (${signal ?? code})\n`);
      process.exit(4);
    }
    if (state === 'stopping' && busy === null) return exitWhenFlushed(0);
    if (state === 'failed') return;
    // Unexpected exit (H4): the request in flight gets 500 INTERNAL, the waiting ones 503.
    if (busy !== null) send(busy.res, INTERNAL);
    busy = null;
    fail(5);
  });

  function handle(req: http.IncomingMessage, res: http.ServerResponse): void {
    // H9, in order: unknown path, method, body size, body shape.
    const route = Object.prototype.hasOwnProperty.call(ROUTES, req.url ?? '') ? ROUTES[req.url!] : undefined;
    if (route === undefined) return send(res, { status: 404, body: { error: 'NOT_FOUND' } });
    if (req.method !== 'POST') {
      return send(res, { status: 405, body: { error: 'METHOD_NOT_ALLOWED' }, headers: { Allow: 'POST' } });
    }
    // A body over the limit is answered 413 at once. The rest of it is read and discarded, so
    // the client can read the answer (closing a socket with unread input resets it), up to a
    // further 1 MiB, after which the connection is dropped.
    const chunks: Buffer[] = [];
    let size = 0;
    let over = false;
    const tooLarge = (): void => {
      over = true;
      chunks.length = 0;
      send(res, { status: 413, body: { error: 'TOO_LARGE' } });
    };
    const declared = req.headers['content-length'];
    if (declared !== undefined && Number(declared) > MAX_BODY) tooLarge();
    req.on('data', (c: Buffer) => {
      size += c.length;
      if (over) {
        if (size > MAX_BODY + (1 << 20)) req.socket.destroy();
        return;
      }
      if (size > MAX_BODY) tooLarge();
      else chunks.push(c);
    });
    req.on('end', () => {
      if (over) return;
      const line = bodyToLine(route, Buffer.concat(chunks));
      if (typeof line !== 'string') return send(res, line);
      if (state !== 'running') return send(res, { status: 503, body: { error: 'UNAVAILABLE' } });
      queue.push({ line, cmd: route.cmd, res });
      dispatch();
    });
  }

  function listen(): void {
    server.on('error', (e: Error) => {
      process.stderr.write(`cannot listen on ${args!.host}:${args!.port}: ${e.message}\n`);
      ledger.stdin!.end();
      process.exit(4);
    });
    server.listen(args!.port, args!.host, () => {
      state = 'running';
      const addr = server.address();
      const port = typeof addr === 'object' && addr !== null ? addr.port : args!.port;
      const host = args!.host.includes(':') ? `[${args!.host}]` : args!.host;
      process.stdout.write(`listening on http://${host}:${port}\n`);
      const stop = (): void => {
        if (state !== 'running') return;
        state = 'stopping';
        server.close();
        server.closeIdleConnections();
        for (const j of queue.splice(0)) unavailable(j);
        finishStop();
      };
      process.on('SIGINT', stop);
      process.on('SIGTERM', stop);
      dispatch();
    });
  }

  // H2: probe with an empty line. Serve opens the store before reading any line, so the first
  // answer (`ERR USAGE`) means the store is open; nothing is stored or changed by it.
  ledger.stdin!.write('\n');
}

// Run when started as a program (the tests import the mapping functions above).
if (process.argv[1] !== undefined && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  main();
}
