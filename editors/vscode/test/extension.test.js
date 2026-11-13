'use strict';
// The extension against a stub of the editor and the real veslint binary, on a fixture of the
// repository (tests/config, with its resolved configuration, which needs no JavaScript runtime).
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const Module = require('node:module');
const { create } = require('./vscode-stub');
const { runVeslint, findConfig, isTypeScriptPath } = require('../lib/runner');

const root = path.resolve(__dirname, '../../..');
const binary = path.join(root, 'veslint');
const fixture = path.join(root, 'tests/config');
const built = fs.existsSync(binary);

/** Waits until `check` gives something, for at most `timeout` ms. */
async function until(check, timeout = 30000) {
  const deadline = Date.now() + timeout;
  for (;;) {
    const value = check();
    if (value) return value;
    if (Date.now() > deadline) throw new Error('timed out');
    await new Promise(resolve => setTimeout(resolve, 20));
  }
}

/** The extension loaded against a new stub of the editor. */
function loadExtension(t) {
  const { vscode, state, TextDocument } = create();
  const load = Module._load;
  Module._load = function (request, ...rest) {
    return request === 'vscode' ? vscode : load.call(this, request, ...rest);
  };
  delete require.cache[require.resolve('../extension')];
  const extension = require('../extension');
  Module._load = load;
  t.after(() => extension.deactivate());
  const activate = () =>
    extension.activate({ subscriptions: [], globalStorageUri: { fsPath: fs.mkdtempSync(path.join(os.tmpdir(), 'veslint-extension-')) } });
  return { vscode, state, TextDocument, activate };
}

test('which files are TypeScript, and which configuration a folder has', () => {
  assert.ok(isTypeScriptPath('a.ts') && isTypeScriptPath('b.TSX') && isTypeScriptPath('c.mts') && isTypeScriptPath('d.cts'));
  assert.ok(!isTypeScriptPath('a.js') && !isTypeScriptPath('a.jsx') && !isTypeScriptPath('a.json'));
  assert.equal(findConfig(fixture, ''), path.join(fixture, 'eslint.config.mjs'));
  assert.equal(findConfig(fixture, 'resolved.json'), path.join(fixture, 'resolved.json'));
  assert.equal(findConfig(fixture, 'missing.json'), null);
  assert.equal(findConfig(path.join(root, 'offsets'), ''), null);
});

test('the runner gives the problems veslint prints', { skip: !built }, async () => {
  const result = await runVeslint({ binary, cwd: fixture, config: path.join(fixture, 'resolved.json'), files: [path.join(fixture, 'base.ts')] });
  const expected = fs
    .readFileSync(path.join(fixture, 'expected.txt'), 'utf8')
    .split('\n')
    .filter(line => line.startsWith('base.ts:'));
  assert.ok(expected.length > 0);
  assert.equal(result.problems.length, expected.length);
  assert.deepEqual(result.errors, []);
  assert.equal(result.cancelled, false);
  assert.match(result.summary, /^\d+ problems in 1 files/);
  assert.deepEqual(
    result.problems.map(problem => `${problem.path}:${problem.line}:${problem.column}\t${problem.rule}\t${problem.messageId}`),
    expected.map(line => line.split('\t').slice(0, 3).join('\t')),
  );
});

test('a binary that does not exist, and a run that is stopped', { skip: !built }, async () => {
  await assert.rejects(runVeslint({ binary: path.join(root, 'no-such-veslint'), cwd: fixture, config: 'resolved.json', files: ['base.ts'] }), /ENOENT/);
  const controller = new AbortController();
  const run = runVeslint({ binary, cwd: fixture, config: path.join(fixture, 'resolved.json'), files: [path.join(fixture, 'base.ts')], signal: controller.signal });
  controller.abort();
  assert.equal((await run).cancelled, true);
  const failed = await runVeslint({ binary, cwd: fixture, config: path.join(fixture, 'base.ts'), files: [path.join(fixture, 'base.ts')] });
  assert.equal(failed.code, 2);
  assert.ok(failed.errors.length > 0);
});

test('the extension shows the problems and offers the fixes', { skip: !built }, async t => {
  const { vscode, state, TextDocument } = create();
  const load = Module._load;
  Module._load = function (request, ...rest) {
    return request === 'vscode' ? vscode : load.call(this, request, ...rest);
  };
  delete require.cache[require.resolve('../extension')];
  const extension = require('../extension');
  Module._load = load;
  t.after(() => extension.deactivate());

  state.folder = fixture;
  state.settings = { path: binary, config: 'resolved.json', severity: 'information' };
  const document = new TextDocument(path.join(fixture, 'base.ts'));
  state.documents.push(document);
  const context = { subscriptions: [], globalStorageUri: { fsPath: fs.mkdtempSync(path.join(os.tmpdir(), 'veslint-extension-')) } };
  extension.activate(context);
  // Open documents are linted when the extension starts.
  await state.commands['veslint.lintOpenFiles']();
  const shown = state.diagnostics.get(document.uri.toString());
  const expected = fs
    .readFileSync(path.join(fixture, 'expected.txt'), 'utf8')
    .split('\n')
    .filter(line => line.startsWith('base.ts:'));
  assert.equal(shown.length, expected.length);
  for (const [index, line] of expected.entries()) {
    const [place, rule] = line.split('\t');
    const [, lineNumber, column] = /:(\d+):(\d+)$/.exec(place);
    assert.equal(shown[index].range.start.line, Number(lineNumber) - 1);
    assert.equal(shown[index].range.start.character, Number(column) - 1);
    assert.equal(shown[index].source, 'veslint');
    if (rule === 'eslint') {
      assert.equal(shown[index].code, 'eslint');
      assert.equal(shown[index].severity, vscode.DiagnosticSeverity.Warning);
    } else {
      assert.equal(shown[index].code.value, rule);
      assert.equal(shown[index].severity, vscode.DiagnosticSeverity.Information);
    }
    assert.ok(shown[index].range.end.isAfter(shown[index].range.start));
    // Where the problem ends, as veslint gives it (ESLint's endLine and endColumn).
    const end = /\tend\t(\d+)\t(\d+)$/.exec(line);
    if (end) {
      assert.equal(shown[index].range.end.line, Number(end[1]) - 1);
      assert.equal(shown[index].range.end.character, Number(end[2]) - 1);
    }
  }

  // Quick fixes: the suggestions of a rule, the fix of an unused directive, and the comment that
  // disables a rule.
  const actionsOf = diagnostic => state.provider.provideCodeActions(document, diagnostic.range, { diagnostics: [diagnostic] });
  const floating = shown.find(diagnostic => diagnostic.code.value === '@typescript-eslint/no-floating-promises');
  const floatingActions = actionsOf(floating);
  assert.deepEqual(
    floatingActions.map(action => action.title).slice(0, 2),
    ['Add void operator to ignore.', 'Add await operator.'],
  );
  assert.equal(floatingActions[0].edit.edits[0].text, 'void ');
  assert.equal(document.offsetAt(floatingActions[0].edit.edits[0].range.start), document.offsetAt(floating.range.start));
  assert.equal(floatingActions.at(-1).title, 'Disable @typescript-eslint/no-floating-promises for this line');
  assert.match(floatingActions.at(-1).edit.edits[0].text, /^\s*\/\/ eslint-disable-next-line @typescript-eslint\/no-floating-promises\n$/);
  const directive = shown.find(diagnostic => diagnostic.code === 'eslint');
  const directiveActions = actionsOf(directive);
  assert.equal(directiveActions.length, 1);
  assert.equal(directiveActions[0].title, 'Fix this eslint problem');
  assert.equal(directiveActions[0].isPreferred, true);

  // Fix all: the fixes that do not overlap, in one edit.
  const fixAll = state.provider.provideCodeActions(document, floating.range, {
    diagnostics: [],
    only: vscode.CodeActionKind.SourceFixAll,
  });
  assert.equal(fixAll.length, 1);
  assert.equal(fixAll[0].kind.value, 'source.fixAll.veslint');
  const withFix = expected.filter(line => line.split('\t').includes('fix')).length;
  assert.ok(withFix > 0);
  assert.equal(fixAll[0].edit.edits.length, withFix);

  // Once the text changes, the fixes of the last run are not offered. A file with unsaved changes
  // is linted with its text, through the server, and then they are offered again.
  document.version++;
  document.isDirty = true;
  assert.deepEqual(actionsOf(floating), []);
  vscode.window.activeTextEditor = { document };
  await state.commands['veslint.lintFile']();
  assert.ok(!state.messages.some(message => message.includes('save it first')));
  assert.equal(state.diagnostics.get(document.uri.toString()).length, expected.length);
  assert.ok(actionsOf(state.diagnostics.get(document.uri.toString())[0]).length > 0);

  // Typing (veslint.run is onType, veslint.typingDelay 0 by default): the unsaved text is linted. A
  // copy of the line of the floating promise is one more problem, on the next line.
  const saved = document.text;
  const floatingLine = Number(/:(\d+):\d+$/.exec(expected.find(line => line.includes('\t@typescript-eslint/no-floating-promises\t')).split('\t')[0])[1]);
  const lines = saved.split('\n');
  document.text = [...lines.slice(0, floatingLine), lines[floatingLine - 1], ...lines.slice(floatingLine)].join('\n');
  document.version++;
  state.handlers.change({ document, contentChanges: [{}] });
  const typed = await until(() => {
    const now = state.diagnostics.get(document.uri.toString());
    return now.length === expected.length + 1 ? now : null;
  });
  assert.equal(typed.filter(diagnostic => diagnostic.code?.value === '@typescript-eslint/no-floating-promises').length, 2);
  assert.ok(typed.some(diagnostic => diagnostic.range.start.line === floatingLine));
  document.text = saved;
  document.version++;

  // Saved again: linted again. Closed: its problems go.
  document.isDirty = false;
  state.handlers.save(document);
  await state.commands['veslint.lintOpenFiles']();
  assert.equal(state.diagnostics.get(document.uri.toString()).length, expected.length);
  assert.equal(actionsOf(state.diagnostics.get(document.uri.toString())[0]).length > 0, true);
  state.handlers.close(document);
  assert.equal(state.diagnostics.has(document.uri.toString()), false);

  // Without a configuration nothing is linted, and a binary that is not there is told once.
  const other = new TextDocument(path.join(root, 'app.ts'));
  state.folder = path.join(root, 'offsets');
  state.settings = { path: binary };
  state.handlers.open(other);
  await state.commands['veslint.lintOpenFiles']();
  assert.equal(state.diagnostics.has(other.uri.toString()), false);
  assert.match(state.status.tooltip, /No configuration/);
  state.folder = fixture;
  state.settings = { path: path.join(root, 'no-such-veslint'), config: 'resolved.json' };
  state.handlers.save(document);
  await state.commands['veslint.lintOpenFiles']();
  await new Promise(resolve => setImmediate(resolve));
  assert.ok(state.messages.some(message => message.includes('cannot run')));
});

test('the unsaved text of a file is seen by the files that import it, until it is saved or reverted', { skip: !built }, async t => {
  const project = fs.mkdtempSync(path.join(os.tmpdir(), 'veslint-project-'));
  fs.cpSync(path.join(root, 'tests/server/project'), project, { recursive: true });
  const { vscode, state, TextDocument, activate } = loadExtension(t);
  state.folder = project;
  state.settings = { path: binary, config: 'rules.json', run: 'manual' };
  const a = new TextDocument(path.join(project, 'a.ts'));
  const b = new TextDocument(path.join(project, 'b.ts'));
  state.documents.push(a, b);
  activate();
  const lintFile = async document => {
    vscode.window.activeTextEditor = { document };
    await state.commands['veslint.lintFile']();
  };
  const rulesOf = document => (state.diagnostics.get(document.uri.toString()) ?? []).map(diagnostic => diagnostic.code.value);
  await lintFile(b);
  assert.deepEqual(rulesOf(b), []);
  // work() made async in a.ts without saving: b.ts, linted after a.ts, sees it.
  const synchronous = a.text;
  const asynchronous = 'export async function work(): Promise<number> {\n  return 1;\n}\n';
  Object.assign(a, { text: asynchronous, isDirty: true, version: a.version + 1 });
  await lintFile(a);
  await lintFile(b);
  assert.deepEqual(rulesOf(b), ['@typescript-eslint/no-floating-promises']);
  // Reverted: b.ts sees the file on disk again.
  Object.assign(a, { text: synchronous, isDirty: false, version: a.version + 1 });
  state.handlers.change({ document: a, contentChanges: [{}] });
  await lintFile(b);
  assert.deepEqual(rulesOf(b), []);
  // Linted while async, edited back, and saved without being linted again: b.ts sees what was saved.
  Object.assign(a, { text: asynchronous, isDirty: true, version: a.version + 1 });
  await lintFile(a);
  await lintFile(b);
  assert.deepEqual(rulesOf(b), ['@typescript-eslint/no-floating-promises']);
  Object.assign(a, { text: synchronous, version: a.version + 1 });
  fs.writeFileSync(a.uri.fsPath, synchronous);
  a.isDirty = false;
  state.handlers.save(a);
  await lintFile(b);
  assert.deepEqual(rulesOf(b), []);
  // Saved async: b.ts sees it from disk.
  fs.writeFileSync(a.uri.fsPath, asynchronous);
  Object.assign(a, { text: asynchronous, version: a.version + 1 });
  state.handlers.save(a);
  await lintFile(b);
  assert.deepEqual(rulesOf(b), ['@typescript-eslint/no-floating-promises']);
});

test('files are linted while typing even when the editor has the defaults of an older version', { skip: !built }, async t => {
  // VS Code keeps the settings of the version it loaded first after an update without a reload:
  // before 0.3.0, veslint.run was onSave by default.
  const { state, TextDocument, activate } = loadExtension(t);
  state.folder = fixture;
  state.settings = { path: binary, config: 'resolved.json' };
  state.defaults = { run: 'onSave' };
  const document = new TextDocument(path.join(fixture, 'base.ts'));
  state.documents.push(document);
  activate();
  assert.ok(state.output.some(line => line.includes('reload the window')));
  await state.commands['veslint.lintOpenFiles']();
  const before = state.diagnostics.get(document.uri.toString()).length;
  const type = async text => {
    Object.assign(document, { text, isDirty: true, version: document.version + 1 });
    state.handlers.change({ document, contentChanges: [{}] });
  };
  const saved = document.text;
  await type(`${saved}\nPromise.resolve(1);\n`);
  await until(() => state.diagnostics.get(document.uri.toString()).length === before + 1);
  // Set by the user, onSave is kept: typing does not lint.
  state.settings.run = 'onSave';
  const linted = state.output.length;
  await type(saved);
  await new Promise(resolve => setTimeout(resolve, 600));
  assert.equal(state.output.length, linted);
  assert.equal(state.diagnostics.get(document.uri.toString()).length, before + 1);
});

test('veslint.typingDelay: 0 by default, the changes of one moment linted once, and a delay kept', { skip: !built }, async t => {
  const { state, TextDocument, activate } = loadExtension(t);
  state.folder = fixture;
  state.settings = { path: binary, config: 'resolved.json' };
  const document = new TextDocument(path.join(fixture, 'base.ts'));
  state.documents.push(document);
  activate();
  await state.commands['veslint.lintOpenFiles']();
  const shown = () => state.diagnostics.get(document.uri.toString()).length;
  const lints = () => state.output.filter(line => / problems in [\d.]+ s /.test(line)).length;
  const before = shown();
  const saved = document.text;
  const type = text => {
    Object.assign(document, { text, isDirty: true, version: document.version + 1 });
    state.handlers.change({ document, contentChanges: [{}] });
  };
  // Five changes at the same moment (as a paste or several cursors give them): one lint, of the
  // last text, which has one more floating promise.
  const linted = lints();
  for (let i = 1; i <= 5; i++) type(`${saved}\n${'Promise.resolve(1);\n'.repeat(i === 5 ? 1 : 0)}// ${i}\n`);
  await until(() => shown() === before + 1);
  await new Promise(resolve => setTimeout(resolve, 200));
  assert.equal(lints(), linted + 1);
  // A delay is waited for: nothing is linted before it.
  state.settings.typingDelay = 400;
  const typedAt = Date.now();
  type(saved);
  await new Promise(resolve => setTimeout(resolve, 150));
  assert.equal(lints(), linted + 1);
  assert.equal(shown(), before + 1);
  await until(() => shown() === before);
  assert.ok(Date.now() - typedAt >= 390);
});

test('a lint does not wait for the answer to an earlier lint of the same file', { skip: !built }, async t => {
  const { VeslintServer } = require('../lib/server');
  const request = VeslintServer.prototype.request;
  const pendingAtSend = [];
  let onSend = () => {};
  VeslintServer.prototype.request = function (...args) {
    pendingAtSend.push(this.pending.length);
    const answer = request.apply(this, args);
    onSend();
    return answer;
  };
  t.after(() => {
    VeslintServer.prototype.request = request;
  });
  const { state, TextDocument, activate } = loadExtension(t);
  state.folder = fixture;
  state.settings = { path: binary, config: 'resolved.json' };
  const document = new TextDocument(path.join(fixture, 'base.ts'));
  state.documents.push(document);
  activate();
  await state.commands['veslint.lintOpenFiles']();
  const shown = () => state.diagnostics.get(document.uri.toString()).length;
  const before = shown();
  const saved = document.text;
  const type = text => {
    Object.assign(document, { text, isDirty: true, version: document.version + 1 });
    state.handlers.change({ document, contentChanges: [{}] });
  };
  // The second change comes as soon as the request of the first one is sent: its lint sends its
  // request while the first one still waits for its answer (which the server may give up), and
  // its problems (one more floating promise) are shown.
  const sent = pendingAtSend.length;
  onSend = () => {
    onSend = () => {};
    type(`${saved}\nPromise.resolve(1);\n`);
  };
  type(`${saved}\n// typed\n`);
  await until(() => pendingAtSend.length >= sent + 2);
  assert.deepEqual(pendingAtSend.slice(sent, sent + 2), [0, 1]);
  await until(() => shown() === before + 1);
});

test('a server that stops is reported, and the next lint starts another', { skip: !built }, async t => {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'veslint-failing-'));
  const failing = path.join(directory, 'veslint-failing');
  const started = path.join(directory, 'started');
  fs.writeFileSync(
    failing,
    `#!/bin/sh\nif [ "$1" = --server ]; then echo >> "${started}"; read line; echo "veslint: the server failed" >&2; exit 1; fi\nexec "${binary}" "$@"\n`,
  );
  fs.chmodSync(failing, 0o755);
  const { vscode, state, TextDocument, activate } = loadExtension(t);
  state.folder = fixture;
  state.settings = { path: failing, config: 'resolved.json', run: 'manual' };
  const document = new TextDocument(path.join(fixture, 'base.ts'));
  state.documents.push(document);
  activate();
  vscode.window.activeTextEditor = { document };
  await state.commands['veslint.lintFile']();
  assert.match(state.status.tooltip, /^the veslint server stopped \(code 1\): veslint: the server failed$/);
  assert.ok(state.messages.some(message => message.includes('the veslint server stopped')));
  assert.equal(state.diagnostics.has(document.uri.toString()), false);
  await state.commands['veslint.lintFile']();
  assert.equal(fs.readFileSync(started, 'utf8').length, 2);
});

test('a veslint without the server mode lints saved files only', { skip: !built }, async t => {
  // A binary that rejects --server, as a veslint from before it does, and runs veslint otherwise.
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'veslint-old-'));
  const old = path.join(directory, 'veslint-old');
  fs.writeFileSync(
    old,
    `#!/bin/sh\nfor a in "$@"; do [ "$a" = --server ] && { echo "veslint: unknown option: --server" >&2; echo "usage: veslint <file.ts>..." >&2; exit 2; }; done\nexec "${binary}" "$@"\n`,
  );
  fs.chmodSync(old, 0o755);
  const { vscode, state, TextDocument } = create();
  const load = Module._load;
  Module._load = function (request, ...rest) {
    return request === 'vscode' ? vscode : load.call(this, request, ...rest);
  };
  delete require.cache[require.resolve('../extension')];
  const extension = require('../extension');
  Module._load = load;
  t.after(() => extension.deactivate());
  state.folder = fixture;
  state.settings = { path: old, config: 'resolved.json' };
  const document = new TextDocument(path.join(fixture, 'base.ts'));
  state.documents.push(document);
  extension.activate({ subscriptions: [], globalStorageUri: { fsPath: fs.mkdtempSync(path.join(os.tmpdir(), 'veslint-extension-')) } });
  await state.commands['veslint.lintOpenFiles']();
  const expected = fs
    .readFileSync(path.join(fixture, 'expected.txt'), 'utf8')
    .split('\n')
    .filter(line => line.startsWith('base.ts:'));
  assert.equal(state.diagnostics.get(document.uri.toString()).length, expected.length);
  assert.ok(state.output.some(line => line.includes('has no server mode')));
  // Unsaved text is not linted then: the problems of the saved text stay.
  document.isDirty = true;
  document.text += '\nPromise.resolve(1);\n';
  document.version++;
  vscode.window.activeTextEditor = { document };
  await state.commands['veslint.lintFile']();
  assert.ok(state.messages.some(message => message.includes('save it first')));
  assert.equal(state.diagnostics.get(document.uri.toString()).length, expected.length);
});
