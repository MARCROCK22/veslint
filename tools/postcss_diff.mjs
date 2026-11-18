// Dev-time: compares the postcss/ port (tools/postcss_dump.v) with postcss 8.5.33, postcss-scss
// 4.0.9, postcss-selector-parser 7.2.1 and eslint-plugin-svelte 3.24.1's TemplateSafeParser on the
// <style> blocks and style attributes of the .svelte files under the directories given (default:
// eslint-plugin-svelte's test fixtures and tests/), and on the selectors of their rules.
// `node tools/postcss_diff.mjs [dir...]` (it builds the dump tool with V=<path to v>).
import fs from 'node:fs';
import path from 'node:path';
import { execFileSync } from 'node:child_process';
import { createRequire } from 'node:module';

const root = path.resolve(import.meta.dirname, '..');
const deps = path.join(root, 'build/upstream/svelte-deps/node_modules');
const require = createRequire(path.join(deps, 'x.js'));
const postcss = require('postcss');
const scss = require('postcss-scss');
const selectorParser = require('postcss-selector-parser');
const { default: TemplateSafeParser } = await import(path.join(deps, 'eslint-plugin-svelte/lib/utils/css-utils/template-safe-parser.js'));

const dirs = process.argv.length > 2 ? process.argv.slice(2) : [path.join(root, 'build/upstream/svelte/packages/eslint-plugin-svelte/tests/fixtures'), path.join(root, 'tests')];
const inputs = [];
const seen = new Set();
const add = (mode, css) => {
  const key = mode + '\0' + css;
  if (!seen.has(key)) {
    seen.add(key);
    inputs.push({ mode, css });
  }
};
const walk = dir => {
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const file = path.join(dir, entry.name);
    if (entry.isDirectory() && entry.name !== 'node_modules') walk(file);
    else if (entry.name.endsWith('.svelte')) {
      const text = fs.readFileSync(file, 'utf8');
      for (const m of text.matchAll(/<style[^>]*>([\s\S]*?)<\/style>/g)) {
        add('css', m[1]);
        add('scss', m[1]);
      }
      for (const m of text.matchAll(/\sstyle=(?:"([^"]*)"|'([^']*)')/g)) add('template', m[1] ?? m[2]);
    }
  }
};
dirs.forEach(walk);
// Edge cases of the tokenizers and parsers.
for (const css of ['a{', 'a{b:c', '}', 'a{b}', '@;', '@media x{a{b:c}}', 'a{b:c d:e}', 'a{b::c}', ':a{}', 'a{b:c !important}', 'a{b:c ! important}',
  'a{_b:c}', 'a{*b:c}', '/* x', 'a{b:url(x y)}', 'a{b:"x', "a{b:'x\\'y'}", 'a{b:(x}', 'a{--x:{a:b}}', 'a{b:c;;}', 'a{};', '@x', '@x y', 'a{b:c}\n/*', 'é{ü:ö}', '😀{b:c}',
  'color: red; top: {x}px', 'a: {b} c', '{x}: y', 'a: b /* c */', 'a: b; /* c', 'a:b:c', 'a b: c', '--x: {y}', 'a: {b ? "c: d" : ""}', 'a: b !important; c: d',
  '.a { .b { c: d } }', '$x: 1; a { b: $x }', 'a { b: #{$c}; }', '@include x;', 'a { &:hover { b: c } }', 'a { b: c; // d\n e: f }', '@media (x) { a { b: c } }', 'a { b: c { d: e } }', 'a { font: { family: x; } }']) {
  add('css', css);
  add('scss', css);
  add('template', css);
}
for (const s of ['a', '.a', '#a', 'a.b#c', ':global(.a)', ':global(.a .b) c', 'a > b + c ~ d', 'a  b', 'a, b', 'a,', '[a=b] c', 'a::before', ':not(:is(a, b))', '.a\\.b', '.\\31 a', '50.5%', 'from', '&.a', '& > b', '*|a', 'a /deep/ b', '/* c */ a', 'a /* c */', ':nth-child(2n+1)', 'a(b)', '.a\n.b', 'a\n  b', ':a(', '[a', '"x" a', 'é.ü']) add('selector', s);
// The selectors of the rules of every block.
for (const input of [...inputs]) {
  if (input.mode !== 'css' && input.mode !== 'scss') continue;
  try {
    const parsed = input.mode === 'css' ? postcss.parse(input.css, { from: 'F' }) : scss.parse(input.css, { from: 'F' });
    parsed.walkRules(rule => add('selector', rule.selector));
  } catch {}
}

const pos = p => ({ offset: p.offset, line: p.line, column: p.column });
const nodeJson = n => {
  const m = { type: n.type, start: pos(n.source.start) };
  if (n.source.end) m.end = pos(n.source.end);
  if (n.type === 'decl') Object.assign(m, { prop: n.prop, value: n.value, important: Boolean(n.important), between: n.raws.between });
  if (n.type === 'rule') m.selector = n.selector;
  if (n.type === 'atrule') Object.assign(m, { name: n.name, params: n.params });
  if (n.nodes) m.nodes = n.nodes.map(nodeJson);
  return m;
};
const selJson = n => {
  const m = { type: n.type === 'string' ? 'str' : n.type };
  if (n.type !== 'root' && n.type !== 'selector' && n.type !== 'attribute') m.value = n.value;
  if (n.source?.start) m.start = `${n.source.start.line}:${n.source.start.column}`;
  if (n.source?.end) m.end = `${n.source.end.line}:${n.source.end.column}`;
  if (n.type === 'root' || n.type === 'selector' || n.type === 'pseudo') m.nodes = n.nodes.map(selJson);
  return m;
};
const expected = inputs.map(({ mode, css }) => {
  try {
    if (mode === 'selector') return selJson(selectorParser().astSync(css));
    if (mode === 'template') {
      const parser = new TemplateSafeParser(new postcss.Input(css));
      parser.parse();
      return nodeJson(parser.root);
    }
    return nodeJson(mode === 'css' ? postcss.parse(css, { from: 'F' }) : scss.parse(css, { from: 'F' }));
  } catch (e) {
    if (mode === 'selector') return { error: true };
    return { error: e.name === 'CssSyntaxError' ? e.message.replace(path.resolve('F'), 'F') : 'TypeError' };
  }
});

const work = fs.mkdtempSync(path.join(root, '../scratch/postcss-diff-'));
fs.writeFileSync(path.join(work, 'inputs.jsonl'), inputs.map(i => JSON.stringify(i)).join('\n') + '\n');
const v = process.env.V ?? 'v';
execFileSync(v, ['-o', path.join(work, 'dump'), path.join(root, 'tools/postcss_dump.v')], { cwd: root, stdio: 'inherit' });
const actual = execFileSync(path.join(work, 'dump'), [path.join(work, 'inputs.jsonl')], { maxBuffer: 1 << 30 }).toString().trim().split('\n').map(l => JSON.parse(l));
const sorted = x => (Array.isArray(x) ? x.map(sorted) : x && typeof x === 'object' ? Object.fromEntries(Object.keys(x).sort().map(k => [k, sorted(x[k])])) : x);
let failures = 0;
const counts = {};
inputs.forEach((input, i) => {
  counts[input.mode] = (counts[input.mode] ?? 0) + 1;
  const a = JSON.stringify(sorted(actual[i])), e = JSON.stringify(sorted(expected[i]));
  if (a !== e) {
    failures++;
    if (failures <= 15) console.log(`DIFF ${input.mode} ${JSON.stringify(input.css).slice(0, 200)}\n  port:    ${a.slice(0, 600)}\n  postcss: ${e.slice(0, 600)}`);
  }
});
console.log(`${inputs.length} inputs (${JSON.stringify(counts)}): ${failures} different`);
fs.rmSync(work, { recursive: true });
process.exit(failures ? 1 : 0);
