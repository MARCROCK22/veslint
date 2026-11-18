// Differential test of svelte_compiler/ (veslint's port of the Svelte 5.56.0 compiler's analysis)
// against svelte's compile():
//
//   node tools/svelte_compile_diff.mjs --out DIR [--v BIN] [--keep] [file.svelte...]
//
// Without files the corpus is every `.svelte` code of tests/rules/svelte/*/upstream.json and the
// .svelte files of eslint-plugin-svelte's and svelte-eslint-parser's fixtures, of svelte's own
// tests (build/upstream/svelte-repo/packages/svelte/tests, a clone of sveltejs/svelte at the
// svelte@5.56.0 tag, when present), the fixtures of tests/rules/svelte and tests/svelte-compile,
// deduplicated, written to
// DIR/corpus. Each file is compiled as eslint-plugin-svelte compiles it, without its source
// transformations: compile(code, {generate: false, customElement: true when <svelte:options> has
// `tag` or `customElement`}). Both sides give the warnings (code, message, start, end) in order,
// or the error; files svelte-eslint-parser rejects (no rule runs on them) are left out. The
// first difference of each file goes to DIR/diff.txt and a summary to stdout. Files whose
// difference tests/svelte-compile/known.txt lists (a path relative to the corpus, a tab, the
// reason) are expected to differ. The V side is BIN (default DIR/svelte_compile_dump, built
// from tools/svelte_compile_dump.v).
//
// Dev-time only: it needs build/upstream/svelte-deps (tests/upstream/README.md).
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { execFileSync } from 'node:child_process';
import { createRequire } from 'node:module';

const ROOT = path.resolve(import.meta.dirname, '..');
const NM = path.join(ROOT, 'build/upstream/svelte-deps/node_modules');
const require = createRequire(path.join(NM, 'x.js'));
const { compile, parse } = require('svelte/compiler');

function walk(dir, out) {
  if (!fs.existsSync(dir)) return;
  for (const e of fs.readdirSync(dir, { withFileTypes: true }).sort((a, b) => (a.name < b.name ? -1 : 1))) {
    if (e.name === 'node_modules') continue;
    const p = path.join(dir, e.name);
    if (e.isDirectory()) walk(p, out);
    else if (e.name.endsWith('.svelte')) out.push(p);
  }
}

function buildCorpus(dir) {
  fs.rmSync(dir, { recursive: true, force: true });
  fs.mkdirSync(dir, { recursive: true });
  const seen = new Map();
  const add = (code, origin) => {
    const hash = crypto.createHash('sha1').update(code).digest('hex').slice(0, 12);
    if (seen.has(hash)) {
      seen.get(hash).origins.push(origin);
      return;
    }
    seen.set(hash, { file: path.join(dir, `${hash}.svelte`), origins: [origin] });
    fs.writeFileSync(path.join(dir, `${hash}.svelte`), code);
  };
  const rulesDir = path.join(ROOT, 'tests/rules/svelte');
  for (const rule of fs.readdirSync(rulesDir).sort()) {
    const file = path.join(rulesDir, rule, 'upstream.json');
    if (!fs.existsSync(file)) continue;
    for (const c of JSON.parse(fs.readFileSync(file, 'utf8')).cases) {
      const f = c.file ?? '';
      if (f.endsWith('.svelte') && !f.endsWith('.svelte.ts') && !f.endsWith('.svelte.js')) add(c.code, c.id);
    }
  }
  const extra = [];
  for (const d of [
    'build/upstream/svelte/packages/eslint-plugin-svelte/tests/fixtures',
    'build/upstream/svelte-eslint-parser/tests/fixtures',
    'build/upstream/svelte-repo/packages/svelte/tests',
    'tests/rules/svelte',
    'tests/svelte-compile',
  ])
    walk(path.resolve(ROOT, d), extra);
  for (const f of extra) {
    let code = fs.readFileSync(f, 'utf8');
    if (code.charCodeAt(0) === 0xfeff) code = code.slice(1);
    add(code, path.relative(ROOT, f));
  }
  const entries = [...seen.values()];
  fs.writeFileSync(path.join(dir, 'origins.json'), JSON.stringify(Object.fromEntries(entries.map(e => [path.basename(e.file), e.origins])), null, 1));
  return entries.map(e => e.file);
}

// isCustomElement is eslint-plugin-svelte's: <svelte:options> with `tag` or `customElement`.
function isCustomElement(code) {
  try {
    const ast = parse(code, { modern: true });
    return !!ast.options?.attributes?.some(a => a.type === 'Attribute' && (a.name === 'tag' || a.name === 'customElement'));
  } catch {
    return false;
  }
}

const LOC = l => (l ? { line: l.line, column: l.column } : null);

function oracle(file) {
  let code = fs.readFileSync(file, 'utf8');
  if (code.charCodeAt(0) === 0xfeff) code = code.slice(1);
  try {
    const r = compile(code, { generate: false, ...(isCustomElement(code) ? { customElement: true } : {}) });
    return {
      warnings: r.warnings.map(w => ({ code: w.code, message: w.message, start: LOC(w.start), end: LOC(w.end) })),
      error: null,
      runes: r.metadata.runes,
    };
  } catch (e) {
    return { warnings: null, error: { code: e.code ?? 'internal', message: e.message, start: LOC(e.start), end: LOC(e.end) } };
  }
}

// ---------------------------------------------------------------------------------------------

const args = process.argv.slice(2);
let out = null;
let bin = null;
let keep = false;
const files = [];
for (let i = 0; i < args.length; i++) {
  if (args[i] === '--out') out = path.resolve(args[++i]);
  else if (args[i] === '--v') bin = path.resolve(args[++i]);
  else if (args[i] === '--keep') keep = true;
  else files.push(path.resolve(args[i]));
}
if (!out) {
  console.error('usage: node tools/svelte_compile_diff.mjs --out DIR [--v BIN] [--keep] [file.svelte...]');
  process.exit(2);
}
fs.mkdirSync(out, { recursive: true });
const corpusDir = path.join(out, 'corpus');
const list = files.length
  ? files
  : keep && fs.existsSync(path.join(corpusDir, 'list.txt'))
    ? fs.readFileSync(path.join(corpusDir, 'list.txt'), 'utf8').split('\n').filter(Boolean)
    : buildCorpus(corpusDir);
if (!files.length) fs.writeFileSync(path.join(corpusDir, 'list.txt'), list.join('\n') + '\n');
const listFile = path.join(out, 'files.txt');
fs.writeFileSync(listFile, list.join('\n') + '\n');

if (!bin) {
  bin = path.join(out, 'svelte_compile_dump');
  execFileSync(process.env.VEXE ?? 'v', ['-o', bin, path.join(ROOT, 'tools/svelte_compile_dump.v')], { cwd: ROOT, stdio: 'inherit', env: { ...process.env, V_C_ERROR_BUG_REPORT_DISABLED: '1', V_MACOS_V3_NO_FALLBACK: '1' } });
}
const vOut = execFileSync(bin, ['json', listFile], { maxBuffer: 1 << 30 }).toString();
const vValues = new Map();
for (const line of vOut.split('\n')) {
  if (!line) continue;
  const v = JSON.parse(line);
  vValues.set(v.path, v);
}

const known = new Map();
const knownFile = path.join(ROOT, 'tests/svelte-compile/known.txt');
if (fs.existsSync(knownFile)) {
  for (const line of fs.readFileSync(knownFile, 'utf8').split('\n')) {
    if (!line || line.startsWith('#')) continue;
    const [p, reason] = line.split('\t');
    known.set(p, reason);
  }
}

const strip = s => JSON.stringify(s);
let same = 0;
let sameNonEmpty = 0;
let differ = 0;
let expected = 0;
let skipped = 0;
let misses = 0;
const diffs = [];
const byCode = new Map();
const unexpected = [];
for (const file of list) {
  const rel = path.relative(corpusDir, file).startsWith('..') ? path.relative(ROOT, file) : path.relative(corpusDir, file);
  const v = vValues.get(file);
  if (!v || v.parse_error !== undefined) {
    skipped++;
    continue;
  }
  if (v.misses) misses += v.misses;
  const o = oracle(file);
  let diff = null;
  if (v.fatal) diff = `V crash: ${v.fatal}`;
  else if (o.error || v.error) {
    if (strip(o.error) !== strip(v.error)) diff = `error: svelte ${strip(o.error)}\n  veslint ${strip(v.error)}`;
  } else {
    const n = Math.max(o.warnings.length, v.warnings.length);
    for (let i = 0; i < n; i++) {
      if (strip(o.warnings[i]) !== strip(v.warnings[i])) {
        diff = `warning ${i}: svelte ${strip(o.warnings[i] ?? null)}\n  veslint ${strip(v.warnings[i] ?? null)}`;
        const code = (o.warnings[i] ?? v.warnings[i]).code;
        byCode.set(code, (byCode.get(code) ?? 0) + 1);
        break;
      }
    }
  }
  if (diff) {
    if (known.has(rel)) expected++;
    else {
      differ++;
      unexpected.push(rel);
    }
    diffs.push(`${rel}${known.has(rel) ? ` (known: ${known.get(rel)})` : ''}\n  ${diff}`);
  } else {
    same++;
    if (o.error || o.warnings.length) sameNonEmpty++;
    if (known.has(rel)) diffs.push(`${rel}: listed in known.txt but identical`);
  }
}
fs.writeFileSync(path.join(out, 'diff.txt'), diffs.join('\n') + '\n');
console.log(`${same} identical (${sameNonEmpty} with warnings or an error), ${expected} known differences, ${differ} unexpected differences, ${skipped} rejected by svelte-eslint-parser (not compared)${misses ? `, ${misses} template expressions without an ESTree node` : ''}`);
if (byCode.size) console.log('first differing warning codes: ' + [...byCode].sort((a, b) => b[1] - a[1]).map(([k, n]) => `${k} ${n}`).join(', '));
if (unexpected.length) console.log(`see ${path.join(out, 'diff.txt')}`);
process.exit(differ ? 1 : 0);
