// The cache of ESLint's results for the test scripts that compare veslint with ESLint
// (reference.sh, cross.sh and upstream_eslint.mjs): ESLint gives the same results for the same
// files with the same configuration and the same versions of ESLint, its plugins, TypeScript and
// Node, so a result is kept under a key made of all of them and ESLint runs again only where one of
// them changed. The cache is build/eslint-cache; VESLINT_NO_ESLINT_CACHE=1 ignores it (nothing is
// read or written).
//
// node tests/rules/eslint_cache.mjs plan FILE... -- CASES...
//   For each cases file, `<cases>\t<rule directory>\t<key>`: the directory of its rule (the closest
//   one above it with an expected.txt) and the key of the files of that directory with the FILEs
//   (the configuration, the scripts that run ESLint); empty directory and key for a cases file
//   outside every rule directory (never cached).
// node tests/rules/eslint_cache.mjs store CACHE_DIR SUFFIX LINES PLAN
//   Writes, for each rule directory of PLAN (the ones ESLint just linted), the lines of LINES that
//   start with `<directory>/` (none, when ESLint gave nothing there) to CACHE_DIR/<key>SUFFIX.
import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';

export const ROOT = path.resolve(import.meta.dirname, '../..');
export const CACHE = path.join(ROOT, 'build/eslint-cache');
export const enabled = !process.env.VESLINT_NO_ESLINT_CACHE;
// Changed when what a cached result is changes.
const CACHE_VERSION = '1';

// The files of a rule directory that are veslint's side (its expected output and the cases of the
// upstream tests, which ESLint does not lint there): they do not change what ESLint gives.
const NOT_LINTED = new Set(['expected.txt', 'fixes.txt', 'limitations.txt', 'fixes.known.txt', 'upstream.json']);

// hashTree adds to `hash` the files under `dir` (paths relative to it, in order, with their bytes);
// a symbolic link is its target, not followed.
export function hashTree(hash, dir, skip = () => false) {
  const walk = relative => {
    const entries = fs.readdirSync(path.join(dir, relative), { withFileTypes: true }).sort((a, b) => (a.name < b.name ? -1 : a.name > b.name ? 1 : 0));
    for (const entry of entries) {
      const rel = path.join(relative, entry.name);
      if (skip(rel, entry)) continue;
      const full = path.join(dir, rel);
      if (entry.isSymbolicLink()) {
        hash.update(`link\0${rel}\0${fs.readlinkSync(full)}\0`);
      } else if (entry.isDirectory()) {
        walk(rel);
      } else if (entry.isFile()) {
        hash.update(`file\0${rel}\0`);
        hash.update(fs.readFileSync(full));
        hash.update('\0');
      }
    }
  };
  walk('');
}

let oracles = null;
// oracleFingerprint: the versions of what gives ESLint's results (Node, and the lockfiles of the
// packages of build/eval and build/upstream), and the built rules of @marcrock22/eslintcf, which
// build/eval takes from git without a version of their own.
export function oracleFingerprint() {
  if (oracles) return oracles;
  const hash = crypto.createHash('sha256');
  hash.update(`${CACHE_VERSION}\0${process.version}\0`);
  for (const file of [
    'build/eval/spider-byte/package.json',
    'build/eval/spider-byte/bun.lock',
    'build/upstream/perfectionist-deps/package-lock.json',
    'build/upstream/seyfert/package-lock.json',
    'build/upstream/types/package-lock.json',
  ]) {
    const full = path.join(ROOT, file);
    hash.update(`${file}\0`);
    if (fs.existsSync(full)) hash.update(fs.readFileSync(full));
    hash.update('\0');
  }
  const marcrock = path.join(ROOT, 'build/eval/spider-byte/node_modules/@marcrock22/eslint/dist');
  if (fs.existsSync(marcrock)) hashTree(hash, fs.realpathSync(marcrock));
  oracles = hash.digest('hex');
  return oracles;
}

// keyOf is the key of `parts` (strings, or Buffers) over the oracles.
export function keyOf(...parts) {
  const hash = crypto.createHash('sha256');
  hash.update(oracleFingerprint());
  for (const part of parts) {
    hash.update('\0');
    hash.update(part);
  }
  return hash.digest('hex');
}

function ruleDirectoryKey(dir, files) {
  const hash = crypto.createHash('sha256');
  hash.update(oracleFingerprint());
  // A FILE is its name and its bytes (a temporary one, such as the rules.json of cross.sh, has a
  // new directory each time).
  for (const file of files) {
    hash.update(`\0${path.basename(file)}\0`);
    hash.update(fs.readFileSync(path.resolve(ROOT, file)));
  }
  hash.update(`\0${dir}\0`);
  hashTree(hash, path.join(ROOT, dir), (rel, entry) => !rel.includes(path.sep) && entry.isFile() && NOT_LINTED.has(entry.name));
  return hash.digest('hex');
}

// ruleDirectoryOf: the closest directory above `file` with an expected.txt, or ''.
function ruleDirectoryOf(file) {
  for (let dir = path.dirname(file); dir.startsWith('tests/rules/'); dir = path.dirname(dir)) {
    if (fs.existsSync(path.join(ROOT, dir, 'expected.txt'))) return dir;
  }
  return '';
}

if (import.meta.url === `file://${process.argv[1]}`) {
  const [command, ...args] = process.argv.slice(2);
  if (command === 'plan') {
    const split = args.indexOf('--');
    const files = args.slice(0, split);
    const keys = new Map();
    const lines = [];
    for (const cases of args.slice(split + 1)) {
      const dir = enabled ? ruleDirectoryOf(cases) : '';
      if (dir && !keys.has(dir)) keys.set(dir, ruleDirectoryKey(dir, files));
      lines.push(`${cases}\t${dir}\t${dir ? keys.get(dir) : ''}\n`);
    }
    process.stdout.write(lines.join(''));
  } else if (command === 'store') {
    const [cacheDir, suffix, linesFile, planFile] = args;
    if (!enabled) process.exit(0);
    const byDir = new Map();
    for (const line of fs.readFileSync(planFile, 'utf8').split('\n')) {
      const [, dir, key] = line.split('\t');
      if (dir) byDir.set(dir, { key, lines: [] });
    }
    // The longest rule directory a line starts with (a file of tests/rules/x/y is not one of tests/rules/x).
    const dirs = [...byDir.keys()].sort((a, b) => b.length - a.length);
    for (const line of fs.readFileSync(linesFile, 'utf8').split('\n')) {
      if (!line) continue;
      const dir = dirs.find(d => line.startsWith(`${d}/`));
      if (dir) byDir.get(dir).lines.push(`${line}\n`);
    }
    fs.mkdirSync(cacheDir, { recursive: true });
    for (const { key, lines } of byDir.values()) {
      const target = path.join(cacheDir, `${key}${suffix}`);
      fs.writeFileSync(`${target}.tmp`, lines.join(''));
      fs.renameSync(`${target}.tmp`, target);
    }
  } else {
    console.error('usage: eslint_cache.mjs plan FILE... -- CASES... | store CACHE_DIR SUFFIX LINES PLAN');
    process.exit(2);
  }
}
