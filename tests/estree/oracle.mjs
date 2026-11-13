// Oracle of the differential test: parses with @typescript-eslint/typescript-estree 8.62.0 and
// serializes the ESTree canonically (see serialize below; tests/estree/main.v writes the same format).
//
//   node oracle.mjs hash <list> [<shard>/<shards>]   prints `path\tstatus\tsha1` per input
//   node oracle.mjs dump <file>                       prints the serialization of one file
//
// status: `ok`, or `esterror` when typescript-estree throws (a syntax error).
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { createRequire } from 'node:module';

// The root of the project.
const ROOT = path.resolve(import.meta.dirname, '../..');

const require = createRequire(path.join(ROOT, 'build/eval/spider-byte/package.json'));
const tsestree = require('@typescript-eslint/typescript-estree');

// Byte offset (UTF-8) of each UTF-16 index of `text`.
function byteOffsets(text) {
	const out = new Int32Array(text.length + 1);
	let b = 0;
	for (let i = 0; i < text.length; i++) {
		out[i] = b;
		const c = text.charCodeAt(i);
		if (c < 0x80) b += 1;
		else if (c < 0x800) b += 2;
		else if (c >= 0xd800 && c <= 0xdbff && i + 1 < text.length) {
			const d = text.charCodeAt(i + 1);
			if (d >= 0xdc00 && d <= 0xdfff) {
				out[i + 1] = b; // the middle of a pair has no byte of its own
				b += 4;
				i++;
				continue;
			}
			b += 3;
		} else b += 3;
	}
	out[text.length] = b;
	return out;
}

function quote(s) {
	let out = '"';
	for (let i = 0; i < s.length; i++) {
		const c = s.charCodeAt(i);
		if (c === 0x22) out += '\\"';
		else if (c === 0x5c) out += '\\\\';
		else if (c >= 0x20 && c < 0x7f) out += s[i];
		else out += '\\u' + c.toString(16).padStart(4, '0');
	}
	return out + '"';
}

function numHex(n) {
	const dv = new DataView(new ArrayBuffer(8));
	dv.setFloat64(0, n);
	return dv.getBigUint64(0).toString(16).padStart(16, '0');
}

const isNode = v => v !== null && typeof v === 'object' && typeof v.type === 'string';
const skipped = new Set(['type', 'parent', 'loc', 'range']);

function scalar(v) {
	if (v === null) return 'null';
	switch (typeof v) {
		case 'boolean':
			return String(v);
		case 'number':
			return `num(${numHex(v)})`;
		case 'string':
			return quote(v);
		case 'bigint':
			return `bigint(${v.toString()})`;
	}
	if (v instanceof RegExp) return 'RegExp';
	throw new Error(`unexpected value ${v}`);
}

export function serialize(ast, text) {
	const offs = byteOffsets(text);
	const lines = [];
	function node(n, ind) {
		lines.push(`${ind}${n.type} ${offs[n.range[0]]}-${offs[n.range[1]]}`);
		props(n, ind);
	}
	function props(obj, ind) {
		for (const key of Object.keys(obj).sort()) {
			if (skipped.has(key)) continue;
			value(key, obj[key], ind);
		}
	}
	function value(key, v, ind) {
		if (v === undefined) return;
		if (Array.isArray(v)) {
			lines.push(`${ind} .${key}[${v.length}]`);
			for (const e of v) {
				if (isNode(e)) node(e, ind + '  ');
				else lines.push(`${ind}  ${scalar(e)}`);
			}
		} else if (isNode(v)) {
			lines.push(`${ind} .${key}:`);
			node(v, ind + '  ');
		} else if (v !== null && typeof v === 'object' && !(v instanceof RegExp)) {
			lines.push(`${ind} .${key}{}`);
			props(v, ind + '  ');
		} else {
			lines.push(`${ind} .${key}=${scalar(v)}`);
		}
	}
	node(ast, '');
	return lines.join('\n') + '\n';
}

export function parseFile(file) {
	let text = fs.readFileSync(file, 'utf8');
	if (text.charCodeAt(0) === 0xfeff) text = text.slice(1);
	const ast = tsestree.parse(text, {
		range: true,
		loc: true,
		comment: false,
		tokens: false,
		jsx: file.endsWith('.tsx'),
		filePath: file,
		suppressDeprecatedPropertyWarnings: true,
		// ORACLE_MODULE=1: what ESLint passes by default (languageOptions.sourceType 'module').
		...(process.env.ORACLE_MODULE ? { sourceType: 'module' } : {}),
	});
	return { ast, text };
}

// traversal lists the enter and leave events of ESLint's Traverser (lib/shared/traverser.js) with
// typescript-eslint's visitor keys, one per line: `+Type start-end` or `-Type start-end`.
const Traverser = require(path.join(ROOT, 'build/eval/spider-byte/node_modules/eslint/lib/shared/traverser.js'));
const { visitorKeys } = require('@typescript-eslint/visitor-keys');
export function traversal(ast, text) {
	const offs = byteOffsets(text);
	const lines = [];
	const ev = (sign, n) => lines.push(`${sign}${n.type} ${offs[n.range[0]]}-${offs[n.range[1]]}`);
	Traverser.traverse(ast, { enter: n => ev('+', n), leave: n => ev('-', n), visitorKeys });
	return lines.join('\n') + '\n';
}

const [mode, arg, shardArg] = process.argv.slice(2);
if (mode === 'dump') {
	const { ast, text } = parseFile(arg);
	process.stdout.write(serialize(ast, text));
} else if (mode === 'traverse') {
	const { ast, text } = parseFile(arg);
	process.stdout.write(traversal(ast, text));
} else if (mode === 'hash') {
	const files = fs.readFileSync(arg, 'utf8').split('\n').filter(Boolean);
	const [shard, shards] = shardArg ? shardArg.split('/').map(Number) : [0, 1];
	const out = [];
	files.forEach((file, i) => {
		if (i % shards !== shard) return;
		let status = 'ok';
		let hash = '-';
		try {
			const { ast, text } = parseFile(file);
			hash = crypto.createHash('sha1').update(serialize(ast, text)).digest('hex');
			hash += ':' + crypto.createHash('sha1').update(traversal(ast, text)).digest('hex');
		} catch (e) {
			status = e && e.name === 'TSError' ? 'esterror' : `crash:${String(e && e.message).replace(/\s+/g, ' ').slice(0, 80)}`;
		}
		out.push(`${file}\t${status}\t${hash}`);
	});
	process.stdout.write(out.join('\n') + (out.length ? '\n' : ''));
}
