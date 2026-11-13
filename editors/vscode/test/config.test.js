'use strict';
// The configuration ESLint resolves, asked once per file and kept until the file changes.
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const Module = require('node:module');
const { execFileSync } = require('node:child_process');
const { create, memento } = require('./vscode-stub');
const { runVeslint, splitResolved } = require('../lib/runner');
const { ConfigCache, isEslintConfig } = require('../lib/configCache');

const root = path.resolve(__dirname, '../../..');
const binary = path.join(root, 'veslint');
const fixture = path.join(root, 'tests/config');
const eslintConfig = path.join(fixture, 'eslint.config.mjs');
// tests/config has no node_modules: its ESLint is the one tests/eval_spider_byte.sh installs, as in tests/run.sh.
const eslintDir = path.join(root, 'build/eval/spider-byte');
let hasBun = true;
try {
  execFileSync('bun', ['--version'], { stdio: 'ignore' });
} catch {
  hasBun = false;
}
const runnable = fs.existsSync(binary) && hasBun && fs.existsSync(path.join(eslintDir, 'node_modules/eslint'));
process.env.VESLINT_ESLINT_DIR = eslintDir;

test('which files are ESLint configurations', () => {
  assert.ok(isEslintConfig('eslint.config.mjs') && isEslintConfig('x/eslint.config.TS') && isEslintConfig('custom.cjs'));
  assert.ok(!isEslintConfig('rules.json') && !isEslintConfig('resolved.json'));
});

test('a resolved configuration is split by file, with absolute paths', () => {
  const resolved = {
    eslint: '10.6.0',
    pluginRules: ['a/b'],
    configs: [{ rules: {} }, { rules: { x: [2] } }],
    files: [
      { path: 'src/a.ts', config: 0 },
      { path: '/elsewhere/b.ts', config: 1 },
      { path: 'ignored.ts', message: 'File ignored because of a matching ignore pattern.' },
    ],
  };
  const byFile = splitResolved(resolved, '/project/eslint.config.mjs');
  assert.deepEqual([...byFile.keys()], ['/project/src/a.ts', '/elsewhere/b.ts', '/project/ignored.ts']);
  const first = JSON.parse(byFile.get('/project/src/a.ts'));
  assert.deepEqual(first.files, [{ path: '/project/src/a.ts', config: 0 }]);
  assert.deepEqual(first.configs, resolved.configs);
  assert.equal(first.eslint, '10.6.0');
  assert.deepEqual(first.pluginRules, ['a/b']);
  assert.equal(JSON.parse(byFile.get('/project/ignored.ts')).files[0].message, 'File ignored because of a matching ignore pattern.');
  assert.equal(splitResolved({ error: 'Key "rules": wrong' }, '/project/eslint.config.mjs').size, 0);
  assert.equal(splitResolved(null, '/project/eslint.config.mjs').size, 0);
});

test('the cache asks ESLint once, and veslint gives the same problems with the copy', { skip: !runnable }, async () => {
  const cache = new ConfigCache(fs.mkdtempSync(path.join(os.tmpdir(), 'veslint-config-')));
  const files = [path.join(fixture, 'base.ts'), path.join(fixture, 'quiet/a.ts')];
  const first = await cache.configsFor({ binary, cwd: fixture, config: eslintConfig, files });
  assert.deepEqual(first.errors, []);
  assert.equal(first.resolved, 2);
  assert.equal(cache.resolutions, 1);
  for (const file of files) {
    const copy = first.configs.get(file);
    assert.notEqual(copy, eslintConfig);
    assert.ok(fs.existsSync(copy));
    const direct = await runVeslint({ binary, cwd: fixture, config: eslintConfig, files: [file] });
    const cached = await runVeslint({ binary, cwd: fixture, config: copy, files: [file] });
    assert.deepEqual(cached.errors, []);
    assert.ok(direct.problems.length > 0);
    assert.deepEqual(cached.problems, direct.problems);
  }
  // Asked again: nothing to resolve.
  const second = await cache.configsFor({ binary, cwd: fixture, config: eslintConfig, files });
  assert.equal(second.resolved, 0);
  assert.equal(cache.resolutions, 1);
  assert.deepEqual([...second.configs], [...first.configs]);
  // A configuration file that changed since: resolved again.
  cache.entries.get(files[0]).modified = -2;
  const third = await cache.configsFor({ binary, cwd: fixture, config: eslintConfig, files });
  assert.equal(third.resolved, 1);
  assert.equal(cache.resolutions, 2);
  // A JSON is given as it is, and clearing removes the copies.
  const json = await cache.configsFor({ binary, cwd: fixture, config: path.join(fixture, 'resolved.json'), files });
  assert.equal(json.resolved, 0);
  assert.equal(json.configs.get(files[0]), path.join(fixture, 'resolved.json'));
  const copies = [...cache.entries.values()].map(entry => entry.json);
  cache.clear();
  assert.ok(copies.every(copy => !fs.existsSync(copy)));
  assert.equal(cache.entries.size, 0);
});

test('the extension resolves once and again when a configuration file changes', { skip: !runnable }, async t => {
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
  // No veslint.config: the eslint.config.mjs at the root of the folder.
  state.settings = { path: binary };
  const base = new TextDocument(path.join(fixture, 'base.ts'));
  const quiet = new TextDocument(path.join(fixture, 'quiet/a.ts'));
  state.documents.push(base, quiet);
  extension.activate({ subscriptions: [], globalStorageUri: { fsPath: fs.mkdtempSync(path.join(os.tmpdir(), 'veslint-extension-')) }, globalState: memento() });
  await state.commands['veslint.lintOpenFiles']();
  const resolvedOnce = state.output.filter(line => line.startsWith('resolved the configuration of'));
  // Both open files were resolved by the first run, in one call.
  assert.deepEqual(resolvedOnce.length, 1);
  assert.match(resolvedOnce[0], /^resolved the configuration of 2 files in /);
  const shown = state.diagnostics.get(base.uri.toString());
  assert.ok(shown.length > 0);
  // Saved again: no new resolution, the same problems.
  state.handlers.save(base);
  await state.commands['veslint.lintOpenFiles']();
  assert.equal(state.output.filter(line => line.startsWith('resolved the configuration of')).length, 1);
  assert.deepEqual(
    state.diagnostics.get(base.uri.toString()).map(diagnostic => diagnostic.message),
    shown.map(diagnostic => diagnostic.message),
  );
  // A configuration file changed: everything is resolved again.
  assert.ok(state.watched.includes('**/eslint.config.{js,mjs,cjs,ts,mts,cts}'));
  await state.handlers['**/eslint.config.{js,mjs,cjs,ts,mts,cts}.onDidChange']();
  assert.equal(state.output.filter(line => line.startsWith('resolved the configuration of')).length, 2);
  // And by hand.
  await state.commands['veslint.reloadConfiguration']();
  assert.equal(state.output.filter(line => line.startsWith('resolved the configuration of')).length, 3);
});
