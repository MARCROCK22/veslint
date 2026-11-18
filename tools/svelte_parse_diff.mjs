// Differential test of the svelte/ module (veslint's parser of .svelte files) against
// svelte-eslint-parser 1.10.1 (svelte 5.56.0) driven by typescript-eslint's parser 8.72.2 given as
// an object (so every file is TypeScript), without types, as ESLint 10 calls it:
//
//   node tools/svelte_parse_diff.mjs --out DIR [--v BIN] [--jobs N] [--keep]
//        [--runes true|false] [--config-runes true|false] [file.svelte...]
//
// --runes sets parserOptions.svelteFeatures.runes and --config-runes parserOptions.svelteConfig
// (`{compilerOptions: {runes}}`) on both sides (without them: unset, and svelte-eslint-parser
// looks for a svelte.config.js above the file, which the corpus directory should not have). The
// five runs (none, --runes true/false, --config-runes true/false) cover every branch of
// svelteParseContext.runes while parsing; with --keep they reuse DIR/corpus.
// Without files the corpus is every `.svelte` code of tests/rules/svelte/*/upstream.json, the
// .svelte fixtures of eslint-plugin-svelte (build/upstream/svelte/packages/eslint-plugin-svelte/
// tests/fixtures) and of svelte-eslint-parser (build/upstream/svelte-eslint-parser/tests/fixtures),
// the probes of veslint-ws/agents/svelte-spec/probes/cases and tests/svelte/*.svelte, deduplicated,
// written to DIR/corpus. For each file both sides give one JSON value (see `canonical`): the
// Program with every Svelte node and ESTree node (no `parent`), its tokens and comments, and every
// code handed to the script parser (`~codes`), or the error (`fatal`). The V side is BIN (default
// DIR/svelte_dump, built from tools/svelte_dump.v). Both are compared after sorting the keys of
// every object; the first difference of each file goes to DIR/diff.txt and a summary to stdout.
// Files whose difference tests/svelte/known.txt lists (a path relative to the corpus and a reason)
// are expected to differ. SVELTE_DIFF_SKIP=key,key leaves top-level keys out.
//
// Dev-time only: it needs build/upstream/svelte-deps (tests/upstream/README.md).
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { spawn } from 'node:child_process';
import { createRequire } from 'node:module';
import os from 'node:os';

const ROOT = path.resolve(import.meta.dirname, '..');
const NM = path.join(ROOT, 'build/upstream/svelte-deps/node_modules');

// ---------------------------------------------------------------------------------------------
// The oracle.

function loadOracle() {
  const require = createRequire(path.join(NM, 'x.js'));
  return { sep: require('svelte-eslint-parser'), ts: require('@typescript-eslint/parser') };
}

function numHex(n) {
  const dv = new DataView(new ArrayBuffer(8));
  dv.setFloat64(0, n);
  return dv.getBigUint64(0).toString(16).padStart(16, '0');
}

const LOC = l => ({ line: l.line, column: l.column });
const locOf = n => ({ start: LOC(n.loc.start), end: LOC(n.loc.end) });

function scalar(v) {
  if (typeof v === 'number') return { $num: numHex(v) };
  if (typeof v === 'bigint') return { $bigint: v.toString() };
  if (v instanceof RegExp) return { $regexp: true };
  return v;
}

// node converts a node (Svelte or ESTree) without `parent` (and the Program without its tokens
// and comments, given once at the top).
function node(n) {
  if (n === null || n === undefined) return null;
  const out = {};
  for (const key of Object.keys(n)) {
    const value = n[key];
    if (key === 'parent' || value === undefined) continue;
    if (n.type === 'Program' && (key === 'tokens' || key === 'comments')) continue;
    if (key === 'range') out.range = [...value];
    else if (key === 'loc') out.loc = locOf(n);
    else out[key] = any(value);
  }
  return out;
}

function any(value) {
  if (Array.isArray(value)) return value.map(any);
  if (value && typeof value === 'object' && typeof value.type === 'string' && value.range) return node(value);
  if (value && typeof value === 'object' && !(value instanceof RegExp)) {
    const out = {};
    for (const [k, e] of Object.entries(value)) if (e !== undefined) out[k] = any(e);
    return out;
  }
  return scalar(value);
}

const token = t => ({ type: t.type, value: t.value, range: [...t.range], loc: locOf(t) });

// scopeSummary is what both sides print of the scope manager: per scope its type, block
// (`Type@start,end`), upper, variables (name, number of definitions, where their references
// are; the global scope's only when used or defined), references (name, where, resolved name)
// and through.
function scopeSummary(sm) {
  const scopes = sm.scopes;
  return scopes.map((s, k) => ({
    type: s.type,
    block: k === 0 ? 'global' : `${s.block.type}@${s.block.range?.[0]},${s.block.range?.[1]}`,
    upper: s.upper ? scopes.indexOf(s.upper) : -1,
    variables: s.variables
      .filter(v => k !== 0 || v.defs.length || v.references.length)
      .map(v => ({ name: v.name, defs: v.defs.length, refs: v.references.map(r => r.identifier.range[0]) })),
    references: s.references.map(r => ({ name: r.identifier.name, at: r.identifier.range[0], resolved: r.resolved ? r.resolved.name : null })),
    through: s.through.map(r => `${r.identifier.name}@${r.identifier.range[0]}`),
  }));
}

// canonical is what both sides print for a file.
// runesOptions are the parser options of --runes and --config-runes (RUNES_OPTIONS, JSON).
const runesOptions = JSON.parse(process.env.RUNES_OPTIONS ?? '{}');

function canonical(oracle, file) {
  let code = fs.readFileSync(file, 'utf8');
  if (code.charCodeAt(0) === 0xfeff) code = code.slice(1);
  const codes = [];
  const parser = {
    ...oracle.ts,
    parseForESLint(c, o) {
      codes.push(c);
      return oracle.ts.parseForESLint(c, o);
    },
  };
  let result;
  try {
    result = oracle.sep.parseForESLint(code, {
      filePath: file,
      parser,
      ecmaVersion: 'latest',
      sourceType: 'module',
      loc: true,
      range: true,
      tokens: true,
      comment: true,
      eslintScopeManager: true,
      eslintVisitorKeys: true,
      ...runesOptions,
    });
  } catch (e) {
    return { fatal: { message: e.message, index: e.index ?? null, lineNumber: e.lineNumber ?? null, column: e.column ?? null } };
  }
  const ast = result.ast;
  return {
    '~scope': scopeSummary(result.scopeManager),
    program: node(ast),
    tokens: (ast.tokens ?? []).map(token),
    comments: (ast.comments ?? []).map(token),
    '~codes': [...codes].sort(),
  };
}
// ---------------------------------------------------------------------------------------------
// Comparison.

// sorted gives the JSON text of a value with the keys of every object sorted.
function sorted(value) {
  if (Array.isArray(value)) return value.map(sorted);
  if (value && typeof value === 'object') {
    const out = {};
    for (const key of Object.keys(value).sort()) out[key] = sorted(value[key]);
    return out;
  }
  return value;
}

// firstDiff is the path of the first difference between two JSON values, with both sides.
function firstDiff(a, b, at = '') {
  if (Array.isArray(a) && Array.isArray(b)) {
    for (let i = 0; i < Math.max(a.length, b.length); i++) {
      if (i >= a.length || i >= b.length) return { at: `${at}[${i}] (length ${a.length} vs ${b.length})`, a: a[i], b: b[i] };
      const d = firstDiff(a[i], b[i], `${at}[${i}]`);
      if (d) return d;
    }
    return null;
  }
  if (a && b && typeof a === 'object' && typeof b === 'object' && !Array.isArray(a) && !Array.isArray(b)) {
    const keys = [...new Set([...Object.keys(a), ...Object.keys(b)])].sort();
    for (const k of keys) {
      if (!(k in a) || !(k in b)) return { at: `${at}.${k} (missing on ${k in a ? 'oracle' : 'V'})`, a: a[k], b: b[k] };
      const d = firstDiff(a[k], b[k], `${at}.${k}`);
      if (d) return d;
    }
    return null;
  }
  return JSON.stringify(a) === JSON.stringify(b) ? null : { at, a, b };
}

// context describes the object a difference is in: its type and range, for the report.
function context(value, at) {
  const parts = at.match(/\.[A-Za-z$_]+|\[\d+\]/g) ?? [];
  let cur = value;
  let last = null;
  for (const p of parts) {
    if (cur && typeof cur === 'object' && cur.type && cur.range) last = `${cur.type}@${cur.range}`;
    cur = p.startsWith('[') ? cur?.[Number(p.slice(1, -1))] : cur?.[p.slice(1)];
    if (cur === undefined) break;
  }
  return last;
}

// ---------------------------------------------------------------------------------------------
// Corpus.

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
    for (const c of JSON.parse(fs.readFileSync(file, 'utf8')).cases) if ((c.file ?? '').endsWith('.svelte') && !(c.file ?? '').endsWith('.svelte.ts') && !(c.file ?? '').endsWith('.svelte.js')) add(c.code, c.id);
  }
  const extra = [];
  for (const d of [
    'build/upstream/svelte/packages/eslint-plugin-svelte/tests/fixtures',
    'build/upstream/svelte-eslint-parser/tests/fixtures',
    '../svelte-spec/probes/cases',
    'tests/svelte',
  ])
    walk(path.resolve(ROOT, d.startsWith('..') ? path.join(ROOT, '../..', d.slice(3)) : d), extra);
  for (const f of extra) {
    let code = fs.readFileSync(f, 'utf8');
    if (code.charCodeAt(0) === 0xfeff) code = code.slice(1);
    add(code, path.relative(ROOT, f));
  }
  const entries = [...seen.values()];
  fs.writeFileSync(path.join(dir, 'origins.json'), JSON.stringify(Object.fromEntries(entries.map(e => [path.basename(e.file), e.origins])), null, 1));
  return entries.map(e => e.file);
}

// ---------------------------------------------------------------------------------------------
// Main.

const args = process.argv.slice(2);
if (args[0] === '--oracle-shard') {
  // Child process: canonical values of the files of a list, one JSON line each.
  const oracle = loadOracle();
  const files = fs.readFileSync(args[1], 'utf8').split('\n').filter(Boolean);
  const out = fs.openSync(args[2], 'w');
  for (const file of files) {
    let value;
    try {
      value = canonical(oracle, file);
    } catch (e) {
      value = { crash: String(e && e.stack) };
    }
    fs.writeSync(out, JSON.stringify({ path: file, value }) + '\n');
  }
  fs.closeSync(out);
  process.exit(0);
}

let out = null;
let vbin = null;
let jobs = os.cpus().length;
let keep = false;
const files = [];
// The runes options: given to the oracle (parser options) and to the V side (its arguments).
const runes = {};
const vRunesArgs = [];
const runesValue = (flag, value) => {
  if (value !== 'true' && value !== 'false') {
    console.error(`${flag} takes true or false`);
    process.exit(2);
  }
  vRunesArgs.push(flag, value);
  return value === 'true';
};
for (let i = 0; i < args.length; i++) {
  if (args[i] === '--runes') runes.svelteFeatures = { runes: runesValue(args[i], args[++i]) };
  else if (args[i] === '--config-runes') runes.svelteConfig = { compilerOptions: { runes: runesValue(args[i], args[++i]) } };
  else if (args[i] === '--out') out = path.resolve(args[++i]);
  else if (args[i] === '--v') vbin = path.resolve(args[++i]);
  else if (args[i] === '--jobs') jobs = Number(args[++i]);
  else if (args[i] === '--keep') keep = true;
  else files.push(path.resolve(args[i]));
}
if (!out) {
  console.error('usage: node tools/svelte_parse_diff.mjs --out DIR [--v BIN] [--jobs N] [--keep] [file.svelte...]');
  process.exit(2);
}
fs.mkdirSync(out, { recursive: true });
vbin ??= path.join(out, 'svelte_dump');
const corpusDir = path.join(out, 'corpus');
const list = files.length ? files : keep && fs.existsSync(path.join(corpusDir, 'list.txt')) ? fs.readFileSync(path.join(corpusDir, 'list.txt'), 'utf8').split('\n').filter(Boolean) : buildCorpus(corpusDir);
if (!files.length) fs.writeFileSync(path.join(corpusDir, 'list.txt'), list.join('\n') + '\n');

const run = (cmd, argv, stdoutFile) =>
  new Promise((resolve, reject) => {
    const fd = fs.openSync(stdoutFile, 'w');
    const child = spawn(cmd, argv, { stdio: ['ignore', fd, 'inherit'], env: { ...process.env, RUNES_OPTIONS: JSON.stringify(runes) } });
    child.on('exit', code => {
      fs.closeSync(fd);
      code === 0 ? resolve() : reject(new Error(`${cmd} exited with ${code}`));
    });
  });

const shards = Array.from({ length: Math.min(jobs, list.length) }, () => []);
list.forEach((f, i) => shards[i % shards.length].push(f));
const t0 = Date.now();
const work = [];
shards.forEach((shard, i) => {
  fs.writeFileSync(path.join(out, `list.${i}.txt`), shard.join('\n') + '\n');
  work.push(run(process.execPath, [import.meta.filename, '--oracle-shard', path.join(out, `list.${i}.txt`), path.join(out, `oracle.${i}.jsonl`)], '/dev/null'));
});
await Promise.all(work);
const tOracle = Date.now() - t0;
const t1 = Date.now();
fs.writeFileSync(path.join(out, 'list.all.txt'), list.join('\n') + '\n');
await run(vbin, ['json', path.join(out, 'list.all.txt'), ...vRunesArgs], path.join(out, 'v.jsonl'));
const tV = Date.now() - t1;

const oracleValues = new Map();
for (let i = 0; i < shards.length; i++)
  for (const line of fs.readFileSync(path.join(out, `oracle.${i}.jsonl`), 'utf8').split('\n').filter(Boolean)) {
    const { path: p, value } = JSON.parse(line);
    oracleValues.set(p, value);
  }
// The V side guesses the message of an error that is TypeScript's syntactic diagnostic of the
// pre-virtual code (tree-sitter has none) and gives that code; veslint's integration asks tsgo.
// The same is done here with the TypeScript of build/upstream/svelte-deps.
const ts = createRequire(path.join(NM, 'x.js'))('typescript');
function withTsDiagnostics(value) {
  const f = value?.fatal;
  if (!f?.ts) return;
  const sf = ts.createSourceFile('x.svelte', f.code, { languageVersion: ts.ScriptTarget.Latest }, true, ts.ScriptKind.TS);
  const d = sf.parseDiagnostics[0];
  delete f.ts;
  delete f.code;
  if (!d) {
    f.message = '(no TypeScript diagnostic)';
    return;
  }
  const lc = sf.getLineAndCharacterOfPosition(d.start);
  f.message = ts.flattenDiagnosticMessageText(d.messageText, '\n');
  f.index = d.start;
  f.lineNumber = lc.line + 1;
  f.column = lc.character;
}
const vValues = new Map();
for (const line of fs.readFileSync(path.join(out, 'v.jsonl'), 'utf8').split('\n').filter(Boolean)) {
  const { path: p, value } = JSON.parse(line);
  withTsDiagnostics(value);
  vValues.set(p, value);
}

const knownFile = path.join(ROOT, 'tests/svelte/known.txt');
const known = new Map();
if (fs.existsSync(knownFile))
  for (const line of fs.readFileSync(knownFile, 'utf8').split('\n')) {
    if (!line || line.startsWith('#')) continue;
    const [p, reason] = line.split('\t');
    known.set(p, reason);
  }

let same = 0;
const diffs = [];
const categories = new Map();
for (const file of list) {
  const o = oracleValues.get(file);
  const v = vValues.get(file);
  // Keys that start with `_` are notes of the V side, not part of the comparison.
  const notes = {};
  if (v)
    for (const k of Object.keys(v))
      if (k.startsWith('_')) {
        notes[k] = v[k];
        delete v[k];
      }
  // SVELTE_DIFF_SKIP=key,key leaves top-level keys out of the comparison (while working on others).
  for (const k of (process.env.SVELTE_DIFF_SKIP ?? '').split(',').filter(Boolean)) {
    if (v) delete v[k];
    if (o) delete o[k];
  }
  const d = firstDiff(sorted(v ?? null), sorted(o ?? null));
  if (!d) {
    same++;
    continue;
  }
  const rel = path.relative(corpusDir, file);
  const where = d.at.replace(/\[\d+\]/g, '[]').replace(/ \(.*$/, '');
  const category = where.split('.').slice(0, 4).join('.');
  categories.set(category, (categories.get(category) ?? 0) + 1);
  diffs.push({ rel, d, ctx: context(o, d.at), known: known.get(rel), notes });
}
const o_fatal = rel => oracleValues.get(path.join(corpusDir, rel))?.fatal || oracleValues.get(rel)?.fatal;
const lines = [];
for (const { rel, d, ctx, known: k, notes } of diffs) {
  const why = notes._scriptError ? ' [tree-sitter: syntax error in the script]' : o_fatal(rel) ? ' [svelte-eslint-parser: fatal error]' : '';
  lines.push(`${rel}${why}${k ? `\t(known: ${k})` : ''}\n  at ${d.at}${ctx ? ` in ${ctx}` : ''}\n  V:      ${JSON.stringify(d.a)?.slice(0, 400)}\n  oracle: ${JSON.stringify(d.b)?.slice(0, 400)}`);
}
fs.writeFileSync(path.join(out, 'diff.txt'), lines.join('\n') + '\n');
const unexpected = diffs.filter(x => !x.known).length;
console.log(`${list.length} files: ${same} identical, ${diffs.length} different (${diffs.length - unexpected} known, ${unexpected} unexpected)`);
console.log(`oracle ${tOracle} ms on ${shards.length} processes, V ${tV} ms on one`);
for (const [c, n] of [...categories].sort((a, b) => b[1] - a[1]).slice(0, 25)) console.log(`  ${n}\t${c}`);
// Only a run over the whole corpus, without runes options (a known difference may be one of the
// runes branches only), can tell that a listed file no longer differs.
const stale = files.length || vRunesArgs.length ? [] : [...known.keys()].filter(k => !diffs.some(x => x.rel === k));
if (stale.length) console.log(`known.txt lists ${stale.length} files that no longer differ: ${stale.slice(0, 5).join(' ')}`);
process.exit(unexpected || stale.length ? 1 : 0);
