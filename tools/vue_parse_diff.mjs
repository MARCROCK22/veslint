// Differential test of the vue/ module (veslint's parser of .vue files) against vue-eslint-parser
// 10.4.2 driven by typescript-eslint's parser 8.72.2, without types, as ESLint 10 calls it:
//
//   node tools/vue_parse_diff.mjs --out DIR [--v BIN] [--jobs N] [--keep] [file.vue...]
//
// Without files the corpus is every `code` with `"sfc": true` of tests/rules/vue/*/upstream.json,
// the probes of .claude/vue-parser-probes/cases and tests/vue/*.vue, deduplicated, written to
// DIR/corpus. For each file both sides give one JSON value (see `canonical` below): the document
// fragment with every V* node and the ESTree of the template expressions, its tokens, comments
// and errors, which child is `templateBody`, the Program's range and tokens, and every code handed
// to the script parser. The V side is BIN (default DIR/vue_dump, built from tools/vue_dump.v).
// Both are compared after sorting the keys of every object; the first difference of each file
// goes to DIR/diff.txt and a summary to stdout. Files whose difference tests/vue/known.txt lists
// (a path relative to the corpus and a reason) are expected to differ.
//
// Dev-time only: it needs build/upstream/vue-deps (tests/upstream/README.md).
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { execFileSync, spawn } from 'node:child_process';
import { createRequire } from 'node:module';
import os from 'node:os';

const ROOT = path.resolve(import.meta.dirname, '..');
const NM = path.join(ROOT, 'build/upstream/vue-deps/node_modules');

// ---------------------------------------------------------------------------------------------
// The oracle.

function loadOracle() {
  const require = createRequire(path.join(NM, 'x.js'));
  return { vep: require('vue-eslint-parser'), ts: require('@typescript-eslint/parser') };
}

function numHex(n) {
  const dv = new DataView(new ArrayBuffer(8));
  dv.setFloat64(0, n);
  return dv.getBigUint64(0).toString(16).padStart(16, '0');
}

const LOC = l => ({ line: l.line, column: l.column });
const locOf = n => ({ start: LOC(n.loc.start), end: LOC(n.loc.end) });

// scalar encodes a property value of an ESTree node: numbers as the bits of the double, bigints
// and regular expressions as tagged objects.
function scalar(v) {
  if (typeof v === 'number') return { $num: numHex(v) };
  if (typeof v === 'bigint') return { $bigint: v.toString() };
  if (v instanceof RegExp) return { $regexp: true };
  return v;
}

const idRef = id => (id ? { name: id.name, range: [...id.range] } : null);

function reference(r) {
  const out = { id: idRef(r.id), mode: r.mode, variable: r.variable ? idRef(r.variable.id) : null };
  if ('isValueReference' in r) out.isValueReference = r.isValueReference;
  if ('isTypeReference' in r) out.isTypeReference = r.isTypeReference;
  return out;
}

function variable(v) {
  return { id: idRef(v.id), kind: v.kind, references: v.references.map(r => [...r.id.range]) };
}

// node converts a V* node or an ESTree node, without `parent` (and without the token, comment and
// error arrays the document and templateBody share, given once at the top).
function node(n) {
  if (n === null || n === undefined) return null;
  const v = n.type.startsWith('V') && !n.type.startsWith('Variable');
  const out = {};
  for (const key of Object.keys(n)) {
    const value = n[key];
    if (key === 'parent' || value === undefined) continue;
    if (v && (key === 'tokens' || key === 'comments' || key === 'errors')) continue;
    if (key === 'range') out.range = [...value];
    else if (key === 'loc') out.loc = locOf(n);
    else if (v && key === 'references') out.references = value.map(reference);
    else if (v && key === 'variables') out.variables = value.map(variable);
    else out[key] = any(value, v);
  }
  return out;
}

function any(value, inV) {
  if (Array.isArray(value)) return value.map(e => any(e, inV));
  if (value && typeof value === 'object' && typeof value.type === 'string' && value.range) return node(value);
  if (value && typeof value === 'object' && !(value instanceof RegExp)) {
    const out = {};
    for (const [k, e] of Object.entries(value)) if (e !== undefined) out[k] = any(e, inV);
    return out;
  }
  return inV ? value : scalar(value);
}

const token = t => ({ type: t.type, value: t.value, range: [...t.range], loc: locOf(t) });

function error(e) {
  const out = { message: e.message, index: e.index, lineNumber: e.lineNumber, column: e.column };
  if (e.code !== undefined) out.code = e.code;
  return out;
}

// scriptLang is getParserLangFromSFC.
function scriptLang(doc) {
  const scripts = doc.children.filter(c => c.type === 'VElement' && c.name === 'script');
  const setup = s => s.startTag.attributes.some(a => !a.directive && a.key.name === 'setup');
  const script = (scripts.length === 2 && scripts.find(setup)) || scripts[0];
  if (!script) return null;
  const lang = script.startTag.attributes.find(a => !a.directive && a.key.name === 'lang');
  return lang?.value?.value || null;
}

function parseWith(oracle, code, file, jsx) {
  const codes = [];
  const parser = {
    parseForESLint(c, o) {
      codes.push(c);
      return oracle.ts.parseForESLint(c, o);
    },
  };
  const result = oracle.vep.parseForESLint(code, {
    filePath: file,
    parser,
    ecmaVersion: 'latest',
    sourceType: 'module',
    ecmaFeatures: { jsx },
    loc: true,
    range: true,
    tokens: true,
    comment: true,
    eslintScopeManager: true,
    eslintVisitorKeys: true,
  });
  return { result, codes };
}

// canonical is what both sides print for a file.
function canonical(oracle, file) {
  let code = fs.readFileSync(file, 'utf8');
  if (code.charCodeAt(0) === 0xfeff) code = code.slice(1);
  let parsed;
  try {
    parsed = parseWith(oracle, code, file, false);
    const doc = parsed.result.services.getDocumentFragment();
    if (scriptLang(doc) === 'tsx') parsed = parseWith(oracle, code, file, true);
  } catch (e) {
    return { fatal: { message: e.message, index: e.index ?? null } };
  }
  const { result, codes } = parsed;
  const doc = result.services.getDocumentFragment();
  const ast = result.ast;
  const templateIndex = ast.templateBody ? doc.children.indexOf(ast.templateBody) : null;
  return {
    document: node(doc),
    templateBody: templateIndex,
    tokens: doc.tokens.map(token),
    comments: doc.comments.map(token),
    errors: doc.errors.map(error),
    program: {
      range: [...ast.range],
      loc: locOf(ast),
      tokens: (ast.tokens ?? []).map(token),
      comments: (ast.comments ?? []).map(token),
    },
    codes: [...codes].sort(),
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
    seen.set(hash, { file: path.join(dir, `${hash}.vue`), origins: [origin] });
    fs.writeFileSync(path.join(dir, `${hash}.vue`), code);
  };
  const rulesDir = path.join(ROOT, 'tests/rules/vue');
  for (const rule of fs.readdirSync(rulesDir).sort()) {
    const file = path.join(rulesDir, rule, 'upstream.json');
    if (!fs.existsSync(file)) continue;
    for (const c of JSON.parse(fs.readFileSync(file, 'utf8')).cases) if (c.sfc) add(c.code, c.id);
  }
  for (const extra of [path.join(ROOT, '.claude/vue-parser-probes/cases'), path.join(ROOT, 'tests/vue')]) {
    if (!fs.existsSync(extra)) continue;
    for (const f of fs.readdirSync(extra).sort()) if (f.endsWith('.vue')) add(fs.readFileSync(path.join(extra, f), 'utf8'), path.relative(ROOT, path.join(extra, f)));
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
for (let i = 0; i < args.length; i++) {
  if (args[i] === '--out') out = path.resolve(args[++i]);
  else if (args[i] === '--v') vbin = path.resolve(args[++i]);
  else if (args[i] === '--jobs') jobs = Number(args[++i]);
  else if (args[i] === '--keep') keep = true;
  else files.push(path.resolve(args[i]));
}
if (!out) {
  console.error('usage: node tools/vue_parse_diff.mjs --out DIR [--v BIN] [--jobs N] [--keep] [file.vue...]');
  process.exit(2);
}
fs.mkdirSync(out, { recursive: true });
vbin ??= path.join(out, 'vue_dump');
const corpusDir = path.join(out, 'corpus');
const list = files.length ? files : keep && fs.existsSync(path.join(corpusDir, 'list.txt')) ? fs.readFileSync(path.join(corpusDir, 'list.txt'), 'utf8').split('\n').filter(Boolean) : buildCorpus(corpusDir);
if (!files.length) fs.writeFileSync(path.join(corpusDir, 'list.txt'), list.join('\n') + '\n');

const run = (cmd, argv, stdoutFile) =>
  new Promise((resolve, reject) => {
    const fd = fs.openSync(stdoutFile, 'w');
    const child = spawn(cmd, argv, { stdio: ['ignore', fd, 'inherit'] });
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
await run(vbin, ['json', path.join(out, 'list.all.txt')], path.join(out, 'v.jsonl'));
const tV = Date.now() - t1;

const oracleValues = new Map();
for (let i = 0; i < shards.length; i++)
  for (const line of fs.readFileSync(path.join(out, `oracle.${i}.jsonl`), 'utf8').split('\n').filter(Boolean)) {
    const { path: p, value } = JSON.parse(line);
    oracleValues.set(p, value);
  }
// The V side guesses the message of an error that is TypeScript's syntactic diagnostic for a
// snippet (tree-sitter has none) and gives in `_ts` the snippet and how its offsets map to the
// file; veslint's integration asks tsgo for that diagnostic. The same is done here with the
// TypeScript of build/upstream/vue-deps, so that the comparison checks everything else exactly.
const ts = createRequire(path.join(NM, 'x.js'))('typescript');
function lineTerminators(text) {
  const out = [];
  for (let i = 0; i < text.length; i++) if (text.charCodeAt(i) === 10) out.push(i + 1);
  return out;
}
function withTsDiagnostics(file, value) {
  if (!value?.errors?.some(e => e._ts)) return;
  let text = fs.readFileSync(file, 'utf8');
  if (text.charCodeAt(0) === 0xfeff) text = text.slice(1);
  const lts = lineTerminators(text);
  for (const e of value.errors) {
    if (!e._ts) continue;
    const { code, tsx, map, adjustEnd } = e._ts;
    delete e._ts;
    const sf = ts.createSourceFile('snippet.vue', code, { languageVersion: ts.ScriptTarget.Latest }, true, tsx ? ts.ScriptKind.TSX : ts.ScriptKind.TS);
    const d = sf.parseDiagnostics[0];
    if (!d) {
      e._noDiagnostic = true;
      continue;
    }
    const index = map[Math.min(d.start, map.length - 1)];
    e.index = index;
    e.message = adjustEnd >= 0 && index >= adjustEnd ? 'Unexpected end of expression.' : ts.flattenDiagnosticMessageText(d.messageText, '\n');
    let lo = 0;
    let hi = lts.length;
    while (lo < hi) {
      const mid = (lo + hi) >> 1;
      if (lts[mid] <= index) lo = mid + 1;
      else hi = mid;
    }
    e.lineNumber = lo + 1;
    e.column = index - (lo === 0 ? 0 : lts[lo - 1]);
  }
}
const vValues = new Map();
for (const line of fs.readFileSync(path.join(out, 'v.jsonl'), 'utf8').split('\n').filter(Boolean)) {
  const { path: p, value } = JSON.parse(line);
  withTsDiagnostics(p, value);
  vValues.set(p, value);
}

const knownFile = path.join(ROOT, 'tests/vue/known.txt');
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
  // The codes are a set: the V side lists them in no particular order.
  if (v?.codes) v.codes.sort();
  // VUE_DIFF_SKIP=key,key leaves top-level keys out of the comparison (while working on others).
  for (const k of (process.env.VUE_DIFF_SKIP ?? '').split(',').filter(Boolean)) {
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
  diffs.push({ rel, d, ctx: context(o, d.at), known: known.get(rel) });
}
const lines = [];
for (const { rel, d, ctx, known: k } of diffs) {
  lines.push(`${rel}${k ? `\t(known: ${k})` : ''}\n  at ${d.at}${ctx ? ` in ${ctx}` : ''}\n  V:      ${JSON.stringify(d.a)?.slice(0, 400)}\n  oracle: ${JSON.stringify(d.b)?.slice(0, 400)}`);
}
fs.writeFileSync(path.join(out, 'diff.txt'), lines.join('\n') + '\n');
const unexpected = diffs.filter(x => !x.known).length;
console.log(`${list.length} files: ${same} identical, ${diffs.length} different (${diffs.length - unexpected} known, ${unexpected} unexpected)`);
console.log(`oracle ${tOracle} ms on ${shards.length} processes, V ${tV} ms on one`);
for (const [c, n] of [...categories].sort((a, b) => b[1] - a[1]).slice(0, 25)) console.log(`  ${n}\t${c}`);
const stale = [...known.keys()].filter(k => !diffs.some(x => x.rel === k));
if (stale.length) console.log(`known.txt lists ${stale.length} files that no longer differ: ${stale.slice(0, 5).join(' ')}`);
process.exit(unexpected || stale.length ? 1 : 0);
