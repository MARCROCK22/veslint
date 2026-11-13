'use strict';
// lib/updater.js and the update command of the extension, with a release made here (a package
// like the real ones, holding a script that answers --version) and a fake GitHub: nothing goes to
// the network.
const test = require('node:test');
const assert = require('node:assert/strict');
const { execFileSync } = require('node:child_process');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const Module = require('node:module');
const updater = require('../lib/updater');
const { create, memento } = require('./vscode-stub');

const root = path.resolve(__dirname, '../../..');
const binary = path.join(root, 'veslint');
const linux = process.platform === 'linux' && process.arch === 'x64';

test('the package of each platform', () => {
  assert.deepEqual(updater.platformPackage('linux', 'x64'), { suffix: 'linux-x64', extension: '.tar.gz', executable: 'veslint' });
  assert.deepEqual(updater.platformPackage('win32', 'x64'), { suffix: 'win32-x64', extension: '.zip', executable: 'veslint.exe' });
  assert.equal(updater.platformPackage('darwin', 'arm64'), null);
  assert.equal(updater.platformPackage('linux', 'arm64'), null);
});

test('versions: what --version prints, and their order', () => {
  assert.equal(updater.parseVersion('veslint 0.12.0'), '0.12.0');
  assert.equal(updater.parseVersion('veslint 1.20.3\n'), '1.20.3');
  assert.equal(updater.parseVersion('veslint: unknown option: --version'), null);
  assert.equal(updater.parseVersion(''), null);
  assert.ok(updater.compareVersions('0.13.0', '0.12.9') > 0);
  assert.ok(updater.compareVersions('0.9.0', '0.10.0') < 0);
  assert.equal(updater.compareVersions('1.2.3', '1.2.3'), 0);
});

test('the version of the veslint binary', { skip: !fs.existsSync(binary) }, async () => {
  const version = JSON.parse(fs.readFileSync(path.join(__dirname, '../package.json'), 'utf8')).version;
  assert.equal(await updater.binaryVersion(binary, root), version);
  assert.equal(await updater.binaryVersion(path.join(root, 'no-such-veslint'), root), null);
});

/** A release `version` with a Linux package whose binary answers `veslint <says>`. */
function fakeRelease(t, version, says = version) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'veslint-release-'));
  t.after(() => fs.rmSync(dir, { recursive: true, force: true }));
  const name = `veslint-${version}-linux-x64`;
  fs.mkdirSync(path.join(dir, name));
  fs.writeFileSync(path.join(dir, name, 'veslint'), `#!/bin/sh\necho "veslint ${says}"\n`, { mode: 0o755 });
  execFileSync('tar', ['-czf', path.join(dir, `${name}.tar.gz`), '-C', dir, name]);
  const url = `https://example.invalid/${name}.tar.gz`;
  const fetchImpl = async target => {
    if (target === url) {
      const bytes = fs.readFileSync(path.join(dir, `${name}.tar.gz`));
      return { ok: true, status: 200, arrayBuffer: async () => bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.length) };
    }
    if (target.endsWith('/releases/latest')) {
      return {
        ok: true,
        status: 200,
        json: async () => ({
          tag_name: `v${version}`,
          html_url: `https://github.com/${updater.repository}/releases/tag/v${version}`,
          body: 'notes',
          assets: [{ name: `${name}.tar.gz`, browser_download_url: url }],
        }),
      };
    }
    return { ok: false, status: 404 };
  };
  return { fetchImpl, url };
}

test('the latest release, from the API of GitHub', async t => {
  const { fetchImpl, url } = fakeRelease(t, '1.2.3');
  const release = await updater.latestRelease(fetchImpl);
  assert.equal(release.version, '1.2.3');
  assert.equal(release.url, `https://github.com/${updater.repository}/releases/tag/v1.2.3`);
  assert.equal(release.assets.get('veslint-1.2.3-linux-x64.tar.gz'), url);
  await assert.rejects(updater.latestRelease(async () => ({ ok: false, status: 403 })), /403/);
  await assert.rejects(updater.latestRelease(async () => ({ ok: true, json: async () => ({ tag_name: 'nightly' }) })), /not a version/);
});

test('installing a release, and the next one', { skip: !linux }, async t => {
  const storage = fs.mkdtempSync(path.join(os.tmpdir(), 'veslint-storage-'));
  t.after(() => fs.rmSync(storage, { recursive: true, force: true }));
  assert.equal(updater.installed(storage), null);
  const first = fakeRelease(t, '1.0.0');
  const one = await updater.install(await updater.latestRelease(first.fetchImpl), storage, { fetchImpl: first.fetchImpl });
  assert.equal(one.version, '1.0.0');
  assert.equal(execFileSync(one.binary, ['--version'], { encoding: 'utf8' }), 'veslint 1.0.0\n');
  assert.deepEqual(updater.installed(storage), one);
  const second = fakeRelease(t, '1.1.0');
  const two = await updater.install(await updater.latestRelease(second.fetchImpl), storage, { fetchImpl: second.fetchImpl });
  assert.deepEqual(updater.installed(storage), two);
  // The version before is removed, and the archive is not kept.
  assert.deepEqual(fs.readdirSync(path.join(storage, 'versions')), ['1.1.0']);
  assert.deepEqual(fs.readdirSync(storage).sort(), ['current.json', 'versions']);
});

test('a package whose binary is another version is not installed', { skip: !linux }, async t => {
  const storage = fs.mkdtempSync(path.join(os.tmpdir(), 'veslint-storage-'));
  t.after(() => fs.rmSync(storage, { recursive: true, force: true }));
  const { fetchImpl } = fakeRelease(t, '2.0.0', '1.9.0');
  await assert.rejects(updater.install(await updater.latestRelease(fetchImpl), storage, { fetchImpl }), /says it is 1\.9\.0, not 2\.0\.0/);
  assert.equal(updater.installed(storage), null);
  const release = await updater.latestRelease(fetchImpl);
  await assert.rejects(updater.install(release, storage, { fetchImpl, platform: 'darwin', arch: 'arm64' }), /no veslint release for darwin-arm64/);
});

/** The extension against the stub, with `fetch` answered by the fake release. */
function loadExtension(t, fetchImpl, globalState = memento()) {
  const { vscode, state } = create();
  const load = Module._load;
  Module._load = function (request, ...rest) {
    return request === 'vscode' ? vscode : load.call(this, request, ...rest);
  };
  delete require.cache[require.resolve('../extension')];
  const extension = require('../extension');
  Module._load = load;
  const realFetch = globalThis.fetch;
  globalThis.fetch = fetchImpl;
  const storage = fs.mkdtempSync(path.join(os.tmpdir(), 'veslint-extension-'));
  t.after(() => {
    extension.deactivate();
    globalThis.fetch = realFetch;
    fs.rmSync(storage, { recursive: true, force: true });
  });
  extension.activate({ subscriptions: [], globalStorageUri: { fsPath: storage }, globalState });
  return { state, storage };
}

test('"veslint: Update veslint" installs the latest release and uses it', { skip: !linux }, async t => {
  const { fetchImpl } = fakeRelease(t, '9.9.9');
  const { state, storage } = loadExtension(t, fetchImpl);
  await state.commands['veslint.update']();
  assert.deepEqual(state.messages, ['veslint updated to 9.9.9.']);
  assert.equal(updater.installed(path.join(storage, 'binary')).version, '9.9.9');
  // Now it is the binary in use: asked again, there is nothing newer.
  state.messages.length = 0;
  await state.commands['veslint.update']();
  assert.deepEqual(state.messages, ['veslint 9.9.9 is the latest version.']);
});

test('with "veslint.path" set, the installed binary is not used, and the message says so', { skip: !linux }, async t => {
  const { fetchImpl } = fakeRelease(t, '9.9.9');
  const { state } = loadExtension(t, fetchImpl);
  state.settings = { path: path.join(root, 'no-such-veslint') };
  await state.commands['veslint.update']();
  assert.equal(state.messages.length, 1);
  assert.match(state.messages[0], /^veslint 9\.9\.9 is installed, but "veslint\.path" \(.*no-such-veslint\) is used\./);
});

test('on its own, the check asks first, and only when the last one was a day ago or more', { skip: !linux }, async t => {
  const { fetchImpl } = fakeRelease(t, '9.9.9');
  // Checked an hour ago: nothing happens.
  const recent = memento({ 'veslint.lastUpdateCheck': Date.now() - 60 * 60 * 1000 });
  loadExtension(t, fetchImpl, recent);
  // Checked two days ago: ten seconds after starting, it asks.
  const old = memento({ 'veslint.lastUpdateCheck': Date.now() - 2 * 24 * 60 * 60 * 1000 });
  t.mock.timers.enable({ apis: ['setTimeout'] });
  const { state } = loadExtension(t, fetchImpl, old);
  t.mock.timers.tick(10000);
  t.mock.timers.reset();
  const deadline = Date.now() + 10000;
  while (state.messages.length === 0 && Date.now() < deadline) await new Promise(resolve => setTimeout(resolve, 20));
  assert.equal(state.messages.length, 1);
  assert.match(state.messages[0], /^veslint 9\.9\.9 is available( \(you have [0-9.]+\))?\. Do you want to update\?$/);
  assert.ok(old.get('veslint.lastUpdateCheck') > Date.now() - 60000);
  assert.ok(recent.get('veslint.lastUpdateCheck') < Date.now() - 30 * 60 * 1000);
});
