'use strict';
// The veslint binary of the GitHub releases: which version is the latest, which one a binary is,
// and installing a release in the extension's storage. Nothing here needs VS Code.
//
// A release has, for each platform, `veslint-<version>-<platform>.tar.gz` (Linux) or `.zip`
// (Windows) with a directory of the same name that holds the binary and the TypeScript 7 compiler
// it runs. It is unpacked with `tar`, which Windows 10 and later also have (and which reads zip).
const { spawn } = require('node:child_process');
const fs = require('node:fs');
const path = require('node:path');

const repository = 'MARCROCK22/veslint';
const latestUrl = `https://api.github.com/repos/${repository}/releases/latest`;

/** The package of a release for a platform and an architecture; null if there is none. */
function platformPackage(platform = process.platform, arch = process.arch) {
  if (platform === 'linux' && arch === 'x64') return { suffix: 'linux-x64', extension: '.tar.gz', executable: 'veslint' };
  if (platform === 'win32' && arch === 'x64') return { suffix: 'win32-x64', extension: '.zip', executable: 'veslint.exe' };
  return null;
}

/** The version `veslint --version` printed (`veslint 0.12.0`); null if it is not one. */
function parseVersion(text) {
  const match = /^veslint (\d+\.\d+\.\d+)\s*$/.exec(text ?? '');
  return match ? match[1] : null;
}

/** Compares two versions `x.y.z`: negative, zero or positive. */
function compareVersions(a, b) {
  const pa = a.split('.').map(Number);
  const pb = b.split('.').map(Number);
  for (let i = 0; i < 3; i++) {
    if (pa[i] !== pb[i]) return pa[i] - pb[i];
  }
  return 0;
}

/**
 * The latest release: its version (the tag without its `v`), its page, its notes and its assets
 * by name.
 */
async function latestRelease(fetchImpl = fetch) {
  const response = await fetchImpl(latestUrl, {
    headers: { Accept: 'application/vnd.github+json', 'User-Agent': 'veslint-vscode' },
  });
  if (!response.ok) throw new Error(`GitHub answered ${response.status} for the latest release`);
  const release = await response.json();
  const version = String(release.tag_name ?? '').replace(/^v/, '');
  if (!/^\d+\.\d+\.\d+$/.test(version)) throw new Error(`the latest release has the tag ${release.tag_name}, not a version`);
  const assets = new Map((release.assets ?? []).map(asset => [asset.name, asset.browser_download_url]));
  return { version, url: release.html_url, notes: release.body ?? '', assets };
}

/** Runs a program and gives its exit code and what it printed; a run longer than `timeout` is killed. */
function run(program, args, { cwd, timeout = 15000 } = {}) {
  return new Promise(resolve => {
    let child;
    try {
      child = spawn(program, args, { cwd, stdio: ['ignore', 'pipe', 'pipe'] });
    } catch (error) {
      resolve({ code: null, stdout: '', stderr: error.message, error });
      return;
    }
    let stdout = '';
    let stderr = '';
    const timer = setTimeout(() => child.kill('SIGKILL'), timeout);
    child.stdout.setEncoding('utf8').on('data', chunk => (stdout += chunk));
    child.stderr.setEncoding('utf8').on('data', chunk => (stderr += chunk));
    child.on('error', error => {
      clearTimeout(timer);
      resolve({ code: null, stdout, stderr, error });
    });
    child.on('close', code => {
      clearTimeout(timer);
      resolve({ code, stdout, stderr });
    });
  });
}

/** The version of a veslint binary (`--version`); null if it cannot be run or does not tell it. */
async function binaryVersion(binary, cwd) {
  const result = await run(binary, ['--version'], { cwd });
  return result.code === 0 ? parseVersion(result.stdout.trim()) : null;
}

/** The binary installed by `install`, if it is still there: its version and its path. */
function installed(storage) {
  try {
    const current = JSON.parse(fs.readFileSync(path.join(storage, 'current.json'), 'utf8'));
    if (typeof current.version === 'string' && typeof current.binary === 'string' && fs.existsSync(current.binary)) return current;
  } catch {
    // Nothing installed yet.
  }
  return null;
}

/**
 * Installs the package of the release for this platform in `storage` (`versions/<version>`), checks
 * that the binary runs and gives its version, and makes it the installed one; the other versions
 * are removed. Gives what `installed` gives.
 */
async function install(release, storage, { fetchImpl = fetch, platform = process.platform, arch = process.arch } = {}) {
  const pkg = platformPackage(platform, arch);
  if (!pkg) throw new Error(`there is no veslint release for ${platform}-${arch}`);
  const name = `veslint-${release.version}-${pkg.suffix}`;
  const url = release.assets.get(name + pkg.extension);
  if (!url) throw new Error(`the release ${release.version} has no ${name}${pkg.extension}`);
  const versions = path.join(storage, 'versions');
  const target = path.join(versions, release.version);
  const archive = path.join(storage, name + pkg.extension);
  fs.mkdirSync(storage, { recursive: true });
  const response = await fetchImpl(url, { headers: { 'User-Agent': 'veslint-vscode' } });
  if (!response.ok) throw new Error(`downloading ${name}${pkg.extension}: ${response.status}`);
  fs.writeFileSync(archive, Buffer.from(await response.arrayBuffer()));
  try {
    fs.rmSync(target, { recursive: true, force: true });
    fs.mkdirSync(target, { recursive: true });
    const unpacked = await run('tar', ['-xf', archive, '-C', target], { timeout: 120000 });
    if (unpacked.code !== 0) throw new Error(`unpacking ${name}${pkg.extension}: ${unpacked.stderr.trim() || unpacked.error?.message || `tar exited with ${unpacked.code}`}`);
  } finally {
    fs.rmSync(archive, { force: true });
  }
  const binary = path.join(target, name, pkg.executable);
  const version = await binaryVersion(binary, target);
  if (version !== release.version) {
    throw new Error(`the downloaded veslint says it is ${version ?? 'no version'}, not ${release.version}`);
  }
  const current = { version, binary };
  fs.writeFileSync(path.join(storage, 'current.json'), JSON.stringify(current));
  for (const other of fs.readdirSync(versions)) {
    // A binary that is still running (Windows locks it) is removed the next time.
    if (other !== release.version) {
      try {
        fs.rmSync(path.join(versions, other), { recursive: true, force: true, maxRetries: 2 });
      } catch {
        // Left for the next update.
      }
    }
  }
  return current;
}

module.exports = { repository, platformPackage, parseVersion, compareVersions, latestRelease, binaryVersion, installed, install };
