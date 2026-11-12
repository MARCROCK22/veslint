'use strict';
// The client of `veslint --server` against the real binary.
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { VeslintServer } = require('../lib/server');
const { runVeslint } = require('../lib/runner');

const root = path.resolve(__dirname, '../../..');
const binary = path.join(root, 'veslint');
const fixture = path.join(root, 'tests/config');
const built = fs.existsSync(binary);

test('the server answers what the command line prints, request after request', { skip: !built }, async t => {
  const server = new VeslintServer(binary, fixture);
  t.after(() => server.stop());
  const file = path.join(fixture, 'base.ts');
  const cli = await runVeslint({ binary, cwd: fixture, config: path.join(fixture, 'resolved.json'), files: [file] });
  for (let i = 0; i < 3; i++) {
    const answer = await server.request({ config: 'resolved.json', files: [file] });
    assert.equal(answer.code, cli.code);
    assert.equal(answer.stdout.split('\n').filter(Boolean).length, cli.problems.length);
  }
  // Unsaved text: one more floating promise.
  const text = fs.readFileSync(file, 'utf8') + '\nPromise.resolve(1);\n';
  const typed = await server.request({ config: 'resolved.json', files: [file], texts: { [file]: text } });
  assert.equal(typed.stdout.split('\n').filter(Boolean).length, cli.problems.length + 1);
  // Forgotten: the file on disk again.
  await server.request({ forget: [file] });
  const again = await server.request({ config: 'resolved.json', files: [file] });
  assert.equal(again.stdout.split('\n').filter(Boolean).length, cli.problems.length);
  // Requests sent together are answered in order. One whose file a later request lints too may be
  // given up (`cancelled`, nothing else); the one for another file and the last one are not.
  const other = path.join(fixture, 'other/a.ts');
  const otherCli = await runVeslint({ binary, cwd: fixture, config: path.join(fixture, 'resolved.json'), files: [other] });
  const together = await Promise.all([
    server.request({ config: 'resolved.json', files: [file] }),
    server.request({ config: 'resolved.json', files: [other] }),
    server.request({ config: 'missing.json', files: [file] }),
  ]);
  assert.ok(together[0].cancelled ? together[0].stdout === '' && together[0].code === 0 : together[0].code === cli.code);
  assert.equal(together[1].cancelled, undefined);
  assert.equal(together[1].code, otherCli.code);
  assert.equal(together[2].cancelled, undefined);
  assert.equal(together[2].code, 2);
});

test('a server that dies fails its requests, and the next request starts another', { skip: !built }, async t => {
  const server = new VeslintServer(binary, fixture);
  t.after(() => server.stop());
  const file = path.join(fixture, 'base.ts');
  await server.request({ config: 'resolved.json', files: [file] });
  const pending = server.request({ config: 'resolved.json', files: [file], texts: { [file]: 'x'.repeat(10) } });
  server.child.kill('SIGKILL');
  await assert.rejects(pending, error => error.code === 'EXITED' || error.code === undefined);
  const answer = await server.request({ config: 'resolved.json', files: [file] });
  assert.ok(answer.stdout.length > 0);
});

test('a binary without the server mode, and one that does not answer', async t => {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'veslint-fake-'));
  const old = path.join(directory, 'old');
  fs.writeFileSync(old, '#!/bin/sh\necho "veslint: unknown option: $1" >&2\necho "usage: veslint <file.ts>..." >&2\nexit 2\n');
  fs.chmodSync(old, 0o755);
  const unsupported = new VeslintServer(old, directory);
  await assert.rejects(unsupported.request({ files: [] }), error => error.code === 'UNSUPPORTED');
  const silent = path.join(directory, 'silent');
  fs.writeFileSync(silent, '#!/bin/sh\nexec sleep 30\n');
  fs.chmodSync(silent, 0o755);
  const stuck = new VeslintServer(silent, directory, { timeout: 300 });
  t.after(() => stuck.stop());
  await assert.rejects(stuck.request({ files: [] }), error => error.code === 'TIMEOUT');
  assert.equal(stuck.running, false);
  const missing = new VeslintServer(path.join(directory, 'nothing'), directory);
  await assert.rejects(missing.request({ files: [] }), error => error.code === 'ENOENT');
});
