// Builds the selector corpus of the esquery differential test (<dir>/selectors.txt, hex WTF-8,
// one per line) and groups of selectors for ESLint's dispatch (<dir>/groups.txt):
// - every string literal and object key of ESLint's no-restricted-syntax, esquery and
//   source-code-traverser tests;
// - selectors generated at random over the node types, attributes, fields and values of the code
//   corpus (<dir>/files.txt);
// - mutations of those (characters deleted, inserted or swapped), mostly syntax errors.
import fs from 'node:fs';
import path from 'node:path';
import { createRequire } from 'node:module';
import { loadFile, encodeHex } from './oracle.mjs';

// The root of the project.
const ROOT = path.resolve(import.meta.dirname, '../..');
// The directory of the corpus (node tests/esquery/selectors.mjs <dir>).
const DIR = process.argv[2];
const require = createRequire(path.join(ROOT, 'build/eval/spider-byte/package.json'));
const tsestree = require('@typescript-eslint/typescript-estree');
const { visitorKeys } = require('@typescript-eslint/visitor-keys');

const out = new Set();
const fromTests = [];
for (const f of ['tests/lib/rules/no-restricted-syntax.js', 'tests/lib/linter/esquery.js', 'tests/lib/linter/source-code-traverser.js']) {
	const text = fs.readFileSync(path.join(ROOT, `build/upstream/eslint/${f}`), 'utf8');
	const ast = tsestree.parse(text, { range: true });
	(function walk(n) {
		if (Array.isArray(n)) return n.forEach(walk);
		if (!n || typeof n !== 'object') return;
		if (n.type === 'Literal' && typeof n.value === 'string') fromTests.push(n.value);
		if (n.type === 'TemplateLiteral' && n.expressions.length === 0) fromTests.push(n.quasis[0].value.cooked);
		if (n.type === 'Property' && n.key.type === 'Identifier' && !n.computed) fromTests.push(n.key.name);
		for (const [k, v] of Object.entries(n)) if (k !== 'parent') walk(v);
	})(ast);
}
for (const s of fromTests) out.add(s);
const nTests = out.size;

// What the code corpus has.
// mulberry32
let seed = 12345;
const rand = () => {
	seed = (seed + 0x6d2b79f5) | 0;
	let t = Math.imul(seed ^ (seed >>> 15), 1 | seed);
	t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
	return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
};
const pick = a => a[Math.floor(rand() * a.length)];
const files = fs.readFileSync(path.join(DIR, 'files.txt'), 'utf8').split('\n').filter(Boolean).map(loadFile);
const types = new Map();
const attrs = new Map(); // path -> sample values
const add = (p, v) => { if (!attrs.has(p)) attrs.set(p, []); const a = attrs.get(p); if (a.length < 30 && !a.includes(v)) a.push(v); };
for (const f of files) for (const { node } of f.entries) {
	types.set(node.type, (types.get(node.type) ?? 0) + 1);
	for (const [k, v] of Object.entries(node)) {
		if (k === 'parent' || k === 'loc' || k === 'range') continue;
		if (v === null || ['string', 'number', 'boolean'].includes(typeof v)) add(k, v);
		else if (Array.isArray(v)) add(`${k}.length`, v.length);
		else if (v && typeof v === 'object' && typeof v.type === 'string') {
			add(`${k}.type`, v.type);
			for (const [k2, v2] of Object.entries(v)) if (k2 !== 'parent' && k2 !== 'loc' && k2 !== 'range' && (v2 === null || ['string', 'number', 'boolean'].includes(typeof v2))) add(`${k}.${k2}`, v2);
		} else if (v && typeof v === 'object' && !(v instanceof RegExp)) for (const [k2, v2] of Object.entries(v)) add(`${k}.${k2}`, v2);
		else if (v instanceof RegExp) { add(`${k}.source`, v.source); add(`${k}.flags`, v.flags); }
	}
	add('parent.type', node.parent ? node.parent.type : null);
	add('range.0', node.range[0]);
	add('loc.start.line', node.loc.start.line);
	add('loc.end.column', node.loc.end.column);
}
const typeNames = [...types.keys()];
const attrPaths = [...attrs.keys()];
const fieldNames = [...new Set(Object.values(visitorKeys).flat())];

const quote = s => {
	const q = rand() < 0.5 ? '"' : "'";
	return q + String(s).replace(/\\/g, '\\\\').replace(q === '"' ? /"/g : /'/g, m => '\\' + m) + q;
};
const reEscape = s => String(s).replace(/[\\^$.*+?()[\]{}|/]/g, '\\$&');
function attrValue(path) {
	const vals = attrs.get(path);
	const v = pick(vals);
	const r = rand();
	if (r < 0.3) return `=${quote(v)}`;
	if (r < 0.4 && typeof v === 'string' && /^[^ [\],():#!=><~+./"'\\]+$/.test(v)) return `${pick(['=', '!='])}${v}`;
	if (r < 0.5 && typeof v === 'number') return `${pick(['=', '<', '>', '<=', '>=', '!='])}${pick([v, v + 1, Math.max(0, v - 1), 0.5, 1.5])}`;
	if (r < 0.62) {
		const s = String(v);
		const part = s.length > 3 ? s.slice(0, 1 + Math.floor(rand() * 3)) : s;
		const anchored = rand() < 0.5 ? `^${reEscape(part)}` : reEscape(part) || '.';
		return `${pick(['=', '=', '!='])}/${anchored}/${pick(['', '', 'i', 'u', 'iu', 's', 'm', 'ims'])}`;
	}
	if (r < 0.72) return `${pick(['=', '!='])}type(${pick(['string', 'number', 'boolean', 'object', 'undefined', 'bigint', 'function'])})`;
	if (r < 0.82) return `${pick(['<', '>', '<=', '>='])}${pick([quote(v), String(Math.floor(rand() * 10)), 'm', '"m"'])}`;
	if (r < 0.9) return `=${typeof v === 'boolean' || v === null ? String(v) : quote(v)}`;
	return '';
}
function atom(depth) {
	const r = rand();
	if (r < 0.35) return rand() < 0.04 ? pick(typeNames).toLowerCase() : pick(typeNames);
	if (r < 0.40) return '*';
	if (r < 0.62) {
		const p = pick(attrPaths);
		return `[${rand() < 0.1 ? ' ' : ''}${p}${rand() < 0.1 ? ' ' : ''}${attrValue(p)}]`;
	}
	if (r < 0.67) return `.${pick(fieldNames)}${rand() < 0.15 ? '.' + pick(fieldNames) : ''}`;
	if (r < 0.74) return pick([':first-child', ':last-child', `:nth-child(${1 + Math.floor(rand() * 3)})`, `:nth-last-child(${1 + Math.floor(rand() * 3)})`, ':nth-child(0)']);
	if (r < 0.80) return ':' + pick(['statement', 'expression', 'declaration', 'function', 'pattern', 'Statement', 'Expression', 'FUNCTION', 'pattern']);
	if (r < 0.81) return ':unknownclass';
	if (depth > 1) return pick(typeNames);
	if (r < 0.88) return `:not(${list(depth + 1)})`;
	if (r < 0.95) return `${pick([':matches(', ':is('])}${list(depth + 1)})`;
	// `:has` walks the subtree of every node it is tried on: only on a type, and once.
	if (depth > 0 || hasUsed) return pick(typeNames);
	hasUsed = true;
	return `${pick(typeNames)}:has(${hasList(depth + 1)})`;
}
function sequence(depth) {
	const n = rand() < 0.7 ? 1 : 2 + Math.floor(rand() * 2);
	let s = '';
	for (let i = 0; i < n; i++) s += atom(depth);
	return (rand() < 0.08 ? '!' : '') + s;
}
const combinator = () => pick([' ', ' > ', '>', ' ~ ', '~', ' + ', '+', '  ', ' >  ']);
function selector(depth) {
	let s = sequence(depth);
	const n = rand() < 0.5 ? 0 : 1 + Math.floor(rand() * 2);
	for (let i = 0; i < n; i++) s += combinator() + sequence(depth);
	return s;
}
function list(depth) {
	let s = selector(depth);
	while (rand() < 0.2) s += pick([',', ', ', ' , ']) + selector(depth);
	return s;
}
function hasList(depth) {
	const rel = () => (rand() < 0.5 ? pick(['> ', '>', '~ ', '+ ', ' ']) : '') + selector(depth);
	let s = rel();
	while (rand() < 0.2) s += ', ' + rel();
	return s;
}
const generated = [];
let hasUsed = false;
while (generated.length < 4000) {
	hasUsed = false;
	const s = rand() < 0.1 ? ` ${list(0)} ` : list(0);
	if (s.length > 120) continue;
	if (!out.has(s)) { out.add(s); generated.push(s); }
}
// Mutations.
const specials = [' ', '[', ']', ',', '(', ')', ':', '#', '!', '=', '>', '<', '~', '+', '.', '"', "'", '/', '\\', '*', 'a', '1'];
let mutated = 0;
while (mutated < 1200) {
	const s = pick(generated);
	const i = Math.floor(rand() * (s.length + 1));
	const r = rand();
	const m = r < 0.4 ? s.slice(0, i) + s.slice(i + 1) : r < 0.8 ? s.slice(0, i) + pick(specials) + s.slice(i) : s.slice(0, i) + s.slice(i, i + 2).split('').reverse().join('') + s.slice(i + 2);
	if (!out.has(m)) { out.add(m); mutated++; }
}
// Hand-written edge cases.
for (const s of ['', ' ', '  *  ', 'Identifier:exit', '[name="a\\nb"]', "[name='\\x']", '[value=/a/ii]', '[value=/(/]', '[value=/[]/]',
	'[value=/\\//]', '[raw=/^"/]', '[name=/\\u{61}/u]', '[name=/\\p{L}/u]', '[name=/ſ/i]', '[name=/K/i]', '[value>"1"]', '[value<=1e3]',
	'[value=1.50]', '[value=.5]', '[value=1.]', '[x=type(  string  )]', '[x=type(string]', ':nth-child(01)', ':nth-child( 2 )',
	':nth-child(99999999999999999999)', '#Identifier', '##Identifier', '!Identifier', '!!Identifier', 'Identifier!', ':has()',
	':has(> Identifier)', ':has(Identifier)', 'Identifier:has(Identifier)', ':not(*)', ':matches()', 'A,', ',A', 'A , B', 'A  >  B',
	'[name.length>3]', '[params.length=0]', '[optional=true]', '[optional=false]', '[computed]', '[regex]', '[regex.flags=/./]',
	'[value=null]', '[value=undefined]', '[parent]', '[parent=null]', '[parent.parent.type="Program"]', '[range.0=0]', '[range=/,/]',
	'[loc.start.line=1]', '[loc.start.column>0]', '[name.constructor]', '[params.map]', '[name.toString=/native/]',
	'[value=type(bigint)]', '[value>1n]', '[value=/^1$/]', '[bigint]', '[value.source]', '[value.flags="g"]', '[value=/\\/a\\//]',
	'[quasis.0.value.cooked]', '[value.raw]', 'TemplateElement[value.cooked=null]', '[members.length>0]', '[assertions]',
	'ImportExpression[attributes]', 'TSEnumMember[computed=false]', '[type=Program]', '[TYPE]', 'identifier', 'IDENTIFIER',
	'Identifier:Statement', ':expression:not(Identifier)', 'MetaProperty > :expression', 'Identifier ~ Identifier',
	'!Identifier ~ Identifier', 'Identifier + Identifier', 'Identifier + !Identifier', '!Identifier + Identifier', '* ~ *', '* + *',
	':first-child:last-child', ':nth-last-child(1)', '[name="日本"]', '[value="😀"]', '[value=/😀/u]', '[value=/./u]', '[value=/^.$/]',
	'Identifier[name=/^\\$/]', 'Literal[value="a\\"b"]', ":matches(Identifier, Literal) > *", 'Program > :statement',
	'.body', '.body.body', '.expression', 'CallExpression > .callee', '.callee.object', '[value="\\u2028"]']) out.add(s);

const all = [...out];
fs.writeFileSync(path.join(DIR, 'selectors.txt'), all.map(encodeHex).join('\n') + '\n');
// Groups for ESLint's dispatch: the option lists of no-restricted-syntax's tests, then random
// groups of generated selectors, some with :exit.
const groups = [];
const nrs = fs.readFileSync(path.join(ROOT, 'build/upstream/eslint/tests/lib/rules/no-restricted-syntax.js'), 'utf8');
for (const m of nrs.matchAll(/options: (\[[^\n]*\])/g)) {
	try {
		// eslint-disable-next-line no-new-func
		const opts = Function(`return ${m[1]}`)();
		groups.push(opts.map(o => (typeof o === 'string' ? o : o.selector)));
	} catch {}
}
const okGenerated = generated.filter(s => s.length < 80);
while (groups.length < 600) {
	const n = 2 + Math.floor(rand() * 8);
	const g = [];
	for (let i = 0; i < n; i++) {
		let s = rand() < 0.15 ? pick(typeNames) : rand() < 0.05 ? '*' : pick(okGenerated);
		if (rand() < 0.2) s += ':exit';
		g.push(s);
	}
	if (rand() < 0.1) g.push(g[0]);
	groups.push(g);
}
fs.writeFileSync(path.join(DIR, 'groups.txt'), groups.map(g => g.map(encodeHex).join(' ')).join('\n') + '\n');
console.log(`selectors: ${all.length} (${nTests} from ESLint's tests, ${generated.length} generated, ${mutated} mutated); groups: ${groups.length}`);
