// Oracle of the esquery differential test: esquery 1.7.0 with the options ESLint 10.6.0 gives it
// (typescript-eslint's visitor keys, eslint-visitor-keys' getKeys as fallback, the JavaScript
// language's matchesSelectorClass, nodeTypeKey 'type') on typescript-estree's tree, with the
// ancestry of ESLint's traversal and every node's `parent` set (as ESLint does before running
// rules).
//
//   node esq_oracle.mjs match <selectors> <files> [<shard>/<shards>]
//       per selector: `index\tstatus\tsha1` of its matches over the files (status: ok, or
//       parseerror)
//   node esq_oracle.mjs show <selectors> <index> <files>   the matches of one selector
//   node esq_oracle.mjs run <groups> <files> [<shard>/<shards>]
//       per group of selectors (one line: indexes into nothing, hex selectors separated by
//       spaces): the listener calls ESLint makes, hashed
//   node esq_oracle.mjs showrun <groups> <index> <files>
//
// Selectors are written one per line as the hexadecimal of their WTF-8 bytes.
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { createRequire } from 'node:module';
import { parseFile } from '../estree/oracle.mjs';

// The root of the project.
const ROOT = path.resolve(import.meta.dirname, '../..');

const require = createRequire(path.join(ROOT, 'build/eval/spider-byte/package.json'));
const esquery = require('esquery');
const evk = require('eslint-visitor-keys');
const { visitorKeys } = require('@typescript-eslint/visitor-keys');
const eslintEsquery = require(path.join(ROOT, 'build/eval/spider-byte/node_modules/eslint/lib/linter/esquery.js'));
const Traverser = require(path.join(ROOT, 'build/eval/spider-byte/node_modules/eslint/lib/shared/traverser.js'));
const jsLanguage = require(path.join(ROOT, 'build/eval/spider-byte/node_modules/eslint/lib/languages/js/index.js'));

export const options = {
	visitorKeys,
	fallback: evk.getKeys,
	matchClass: jsLanguage.matchesSelectorClass,
	nodeTypeKey: jsLanguage.nodeTypeKey,
};

// decodeHex reads WTF-8 bytes (lone surrogates included) back into a JavaScript string.
export function decodeHex(hex) {
	const b = Buffer.from(hex, 'hex');
	let s = '';
	for (let i = 0; i < b.length; ) {
		const c = b[i];
		let cp, n;
		if (c < 0x80) { cp = c; n = 1; }
		else if (c >= 0xf0) { cp = ((c & 7) << 18) | ((b[i + 1] & 63) << 12) | ((b[i + 2] & 63) << 6) | (b[i + 3] & 63); n = 4; }
		else if (c >= 0xe0) { cp = ((c & 15) << 12) | ((b[i + 1] & 63) << 6) | (b[i + 2] & 63); n = 3; }
		else { cp = ((c & 31) << 6) | (b[i + 1] & 63); n = 2; }
		s += cp >= 0x10000 ? String.fromCodePoint(cp) : String.fromCharCode(cp);
		i += n;
	}
	return s;
}

export function encodeHex(s) {
	const out = [];
	for (let i = 0; i < s.length; i++) {
		let cp = s.charCodeAt(i);
		if (cp >= 0xd800 && cp <= 0xdbff && i + 1 < s.length) {
			const d = s.charCodeAt(i + 1);
			if (d >= 0xdc00 && d <= 0xdfff) { cp = 0x10000 + ((cp - 0xd800) << 10) + (d - 0xdc00); i++; }
		}
		if (cp < 0x80) out.push(cp);
		else if (cp < 0x800) out.push(0xc0 | (cp >> 6), 0x80 | (cp & 63));
		else if (cp < 0x10000) out.push(0xe0 | (cp >> 12), 0x80 | ((cp >> 6) & 63), 0x80 | (cp & 63));
		else out.push(0xf0 | (cp >> 18), 0x80 | ((cp >> 12) & 63), 0x80 | ((cp >> 6) & 63), 0x80 | (cp & 63));
	}
	return Buffer.from(out).toString('hex');
}

// Byte offset of each UTF-16 index (as in oracle.mjs).
function byteOffsets(text) {
	const out = new Int32Array(text.length + 1);
	let b = 0;
	for (let i = 0; i < text.length; i++) {
		out[i] = b;
		const c = text.charCodeAt(i);
		if (c < 0x80) b += 1;
		else if (c < 0x800) b += 2;
		else if (c >= 0xd800 && c <= 0xdbff && i + 1 < text.length && text.charCodeAt(i + 1) >= 0xdc00 && text.charCodeAt(i + 1) <= 0xdfff) {
			out[i + 1] = b; b += 4; i++; continue;
		} else b += 3;
	}
	out[text.length] = b;
	return out;
}

// loadFile parses a file and lists its nodes in traversal order with their ancestry, and the
// enter/leave steps.
export function loadFile(file) {
	const { ast, text } = parseFile(file);
	const offs = byteOffsets(text);
	const steps = [];
	Traverser.traverse(ast, {
		enter(node, parent) { node.parent = parent; steps.push({ node, leave: false }); },
		leave(node) { steps.push({ node, leave: true }); },
		visitorKeys,
	});
	const entries = [];
	const ancestry = [];
	for (const s of steps) {
		if (s.leave) { ancestry.shift(); continue; }
		entries.push({ node: s.node, ancestry: ancestry.slice() });
		ancestry.unshift(s.node);
	}
	const label = n => `${n.type} ${offs[n.range[0]]}-${offs[n.range[1]]}`;
	return { file, entries, steps, label };
}

function matchList(f, sel) {
	const lines = [`F ${f.file}`];
	try {
		for (const e of f.entries) if (esquery.matches(e.node, sel, e.ancestry, options)) lines.push(f.label(e.node));
	} catch (err) {
		lines.push(`THROW`);
	}
	return lines.join('\n') + '\n';
}

// runGroup ports ESLint's listener calls for the selectors of a group (see esquery/eslint.v).
function runGroup(f, sources) {
	const lines = [`F ${f.file}`];
	let parsed;
	try {
		const seen = new Map();
		sources.forEach((s, i) => seen.set(s, i));
		parsed = [...seen].map(([s, i]) => ({ sel: eslintEsquery.parse(s), index: i }));
	} catch (err) {
		return 'PARSEERROR\n';
	}
	parsed.sort((a, b) => a.sel.compare(b.sel));
	const ancestry = [];
	try {
		for (const step of f.steps) {
			const node = step.node;
			if (step.leave) ancestry.shift();
			for (const p of parsed) {
				if (p.sel.isExit !== step.leave) continue;
				if (p.sel.nodeTypes && !p.sel.nodeTypes.includes(node.type)) continue;
				if (eslintEsquery.matches(node, p.sel.root, ancestry, options)) lines.push(`${step.leave ? '-' : '+'}${p.index} ${f.label(node)}`);
			}
			if (!step.leave) ancestry.unshift(node);
		}
	} catch (err) {
		lines.push('THROW');
	}
	return lines.join('\n') + '\n';
}

const sha1 = s => crypto.createHash('sha1').update(s).digest('hex');
const readLines = p => fs.readFileSync(p, 'utf8').split('\n').filter(Boolean);
const shardOf = a => (a ? a.split('/').map(Number) : [0, 1]);

const [mode, ...args] = process.argv.slice(2);
if (mode === 'match' || mode === 'show') {
	const sels = readLines(args[0]).map(decodeHex);
	const which = mode === 'show' ? Number(args[1]) : -1;
	const files = readLines(mode === 'show' ? args[2] : args[1]).map(loadFile);
	const [shard, shards] = mode === 'show' ? [0, 1] : shardOf(args[2]);
	const out = [];
	sels.forEach((source, i) => {
		if (which >= 0 ? i !== which : i % shards !== shard) return;
		let sel;
		try {
			sel = esquery.parse(source);
		} catch {
			out.push(`${i}\tparseerror\t-`);
			return;
		}
		const text = files.map(f => matchList(f, sel)).join('');
		if (mode === 'show') process.stdout.write(text);
		else out.push(`${i}\tok\t${sha1(text)}`);
	});
	if (mode === 'match') process.stdout.write(out.join('\n') + '\n');
	else if (out.length) process.stdout.write(out.join('\n') + '\n');
} else if (mode === 'run' || mode === 'showrun') {
	const groups = readLines(args[0]).map(l => l.split(' ').map(decodeHex));
	const which = mode === 'showrun' ? Number(args[1]) : -1;
	const files = readLines(mode === 'showrun' ? args[2] : args[1]).map(loadFile);
	const [shard, shards] = mode === 'showrun' ? [0, 1] : shardOf(args[2]);
	const out = [];
	groups.forEach((sources, i) => {
		if (which >= 0 ? i !== which : i % shards !== shard) return;
		const text = files.map(f => runGroup(f, sources)).join('');
		if (mode === 'showrun') process.stdout.write(text);
		else out.push(`${i}\t${sha1(text)}`);
	});
	if (mode === 'run') process.stdout.write(out.join('\n') + '\n');
}
