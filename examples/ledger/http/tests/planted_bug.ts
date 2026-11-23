// V3: planted bugs. A deliberately wrong copy of the server must make the HTTP differential test
// (V2) fail, which shows that the test can fail.
//
//   node examples/ledger/http/tests/planted_bug.ts
//
// Each mutant is server.ts with one textual change, written to a temporary directory and run
// through the same adapter, generator and oracle as V2. The real server.ts is not touched.

import * as fs from 'node:fs';
import * as path from 'node:path';
import { spawnSync } from 'node:child_process';
import { SERVER, HTTP_DIR, LEDGER, ORACLE, tmpdir, check, summary } from './lib.ts';

const MUTANTS: { name: string; from: string; to: string }[] = [
  {
    name: '/transfer with from and to swapped',
    from: "'/transfer': { cmd: 'transfer', fields: ['from', 'to', 'amount'] },",
    to: "'/transfer': { cmd: 'transfer', fields: ['to', 'from', 'amount'] },",
  },
  {
    name: 'INSUFFICIENT_FUNDS reported as BALANCE_LIMIT',
    from: 'export function answerToReply(line: string, cmd: string): Reply {',
    to: "export function answerToReply(line: string, cmd: string): Reply {\n  if (line === 'ERR INSUFFICIENT_FUNDS') line = 'ERR BALANCE_LIMIT';",
  },
  {
    name: 'UNKNOWN_ACCOUNT answered 422 instead of 404',
    from: "return { status: 404, body: { error: 'UNKNOWN_ACCOUNT', account: w[2] } };",
    to: "return { status: 422, body: { error: 'UNKNOWN_ACCOUNT', account: w[2] } };",
  },
  {
    name: 'balances converted to JavaScript numbers',
    from: "{ status: 200, body: { balance: w[1] } }",
    to: "{ status: 200, body: { balance: String(Number(w[1])) } }",
  },
];

const src = fs.readFileSync(SERVER, 'utf8');
const d = tmpdir();
const difftest = path.resolve(HTTP_DIR, '..', '..', '..', 'tools', 'difftest.py');
const gen = path.resolve(HTTP_DIR, '..', 'impl', 'tests', 'gen_commands.py');
for (const m of MUTANTS) {
  check(src.split(m.from).length === 2, `${m.name}: the text to mutate occurs exactly once`);
  const file = path.join(d, `mutant-${MUTANTS.indexOf(m)}.ts`);
  fs.writeFileSync(file, src.replace(m.from, m.to));
  const sut = `${process.execPath} ${path.join(HTTP_DIR, 'adapter.ts')} {dir} --server ${file} --ledger ${LEDGER}`;
  const p = spawnSync('python3', ['-I', difftest, '--sut', sut, '--oracle', ORACLE, '--gen', gen,
    '--runs', '30', '--length', '200'], { encoding: 'utf8' });
  const caught = p.status === 1 && p.stdout.includes('DISAGREEMENT');
  check(caught, `${m.name}: difftest exit ${p.status}, want 1 with a disagreement\n${p.stdout}${p.stderr}`);
  if (caught) {
    const lines = p.stdout.trim().split('\n');
    console.log(`planted_bug: '${m.name}' caught: ${lines[0].replace('difftest: ', '')}`);
    console.log(lines.slice(1).map((l) => '    ' + l).join('\n'));
  }
}
fs.rmSync(d, { recursive: true, force: true });
process.exit(summary('planted_bug'));
