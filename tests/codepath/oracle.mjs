// Oracle of the differential test of the code path analysis: lints each file with ESLint 10.6.0
// and typescript-eslint's parser 8.62.0, with a rule that records every event its listeners get
// (`*`, `*:exit` and the seven code path events), in the order ESLint calls them, and writes them
// canonically (tests/codepath/main.v writes the same format).
//
//   node cpa_oracle.mjs hash <list> [<shard>/<shards>]   prints `path\tstatus\tsha1` per input
//   node cpa_oracle.mjs dump <file>                       prints the events of one file
//
// status: `ok`, or `esterror` when the parser fails (a syntax error).
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { createRequire } from 'node:module';

// The root of the project.
const ROOT = path.resolve(import.meta.dirname, '../..');

const require = createRequire(path.join(ROOT, 'build/eval/spider-byte/package.json'));
const { Linter } = require('eslint');
const tsParser = require('@typescript-eslint/parser');

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
				out[i + 1] = b;
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

let lines = [];
let offs = null;

const nodeText = n => `${n.type} ${offs[n.range[0]]}-${offs[n.range[1]]}`;
const ids = segs => `[${segs.map(s => s.id).join(',')}]`;
const segmentText = s =>
	`r=${+s.reachable} used=${+s.internal.used} prev=${ids(s.prevSegments)} next=${ids(s.nextSegments)} allPrev=${ids(
		s.allPrevSegments,
	)} allNext=${ids(s.allNextSegments)} looped=${ids(s.internal.loopedPrevSegments)}`;

// The traversals of tests/codepath/main.v's walk.
function walk(codePath, options, skipEvery, breakAt) {
	const out = [];
	codePath.traverseSegments(options, (segment, controller) => {
		const k = out.length;
		out.push(segment);
		if (skipEvery > 0 && k % skipEvery === 1) controller.skip();
		if (breakAt > 0 && k === breakAt) controller.break();
	});
	return out;
}

function codePathText(cp) {
	const plain = walk(cp, {}, 0, 0);
	const skipped = walk(cp, {}, 3, 0);
	const broken = walk(cp, {}, 0, 3);
	const first = plain.length > 1 ? ids(walk(cp, { first: plain[1] }, 0, 0)) : '-';
	const last = cp.finalSegments.length > 0 ? ids(walk(cp, { last: cp.finalSegments[0] }, 0, 0)) : '-';
	return `initial=${cp.initialSegment.id} final=${ids(cp.finalSegments)} returned=${ids(cp.returnedSegments)} thrown=${ids(
		cp.thrownSegments,
	)} children=[${cp.childCodePaths.map(c => c.id).join(',')}] traverse=${ids(plain)} skip=${ids(skipped)} break=${ids(
		broken,
	)} first=${first} last=${last}`;
}

const recorder = {
	meta: { type: 'problem', schema: [] },
	create() {
		const seg = name => (segment, node) => lines.push(`${name} ${segment.id} @${nodeText(node)} ${segmentText(segment)}`);
		return {
			'*': node => lines.push(`+${nodeText(node)}`),
			'*:exit': node => lines.push(`-${nodeText(node)}`),
			onCodePathStart: (cp, node) =>
				lines.push(`onCodePathStart ${cp.id} origin=${cp.origin} upper=${cp.upper ? cp.upper.id : '-'} @${nodeText(node)}`),
			onCodePathEnd: (cp, node) => lines.push(`onCodePathEnd ${cp.id} @${nodeText(node)} ${codePathText(cp)}`),
			onCodePathSegmentStart: seg('onCodePathSegmentStart'),
			onCodePathSegmentEnd: seg('onCodePathSegmentEnd'),
			onUnreachableCodePathSegmentStart: seg('onUnreachableCodePathSegmentStart'),
			onUnreachableCodePathSegmentEnd: seg('onUnreachableCodePathSegmentEnd'),
			onCodePathSegmentLoop: (from, to, node) => lines.push(`onCodePathSegmentLoop ${from.id} ${to.id} @${nodeText(node)}`),
		};
	},
};

const linter = new Linter();
const config = [
	{
		files: ['**/*.ts', '**/*.tsx', '**/*.mts', '**/*.cts'],
		languageOptions: { parser: tsParser },
		// Configuration comments of the corpus (`/* eslint … */`) would enable other rules.
		linterOptions: { noInlineConfig: true, reportUnusedDisableDirectives: 'off' },
		plugins: { rec: { rules: { events: recorder } } },
		rules: { 'rec/events': 'error' },
	},
];

// run returns the events of a file, or null when it does not parse.
export function run(file) {
	let text = fs.readFileSync(file, 'utf8');
	if (text.charCodeAt(0) === 0xfeff) text = text.slice(1);
	offs = byteOffsets(text);
	lines = [];
	const messages = linter.verify(text, config, { filename: `file${path.extname(file)}` });
	const fatal = messages.find(m => m.fatal);
	if (fatal) return null;
	const other = messages.find(m => m.ruleId !== null && m.ruleId !== 'rec/events');
	if (other) throw new Error(other.message);
	return lines.join('\n') + '\n';
}

const [mode, arg, shardArg] = process.argv.slice(2);
if (mode === 'dump') {
	const out = run(arg);
	if (out === null) {
		console.error('parse error');
		process.exit(1);
	}
	process.stdout.write(out);
} else if (mode === 'hash') {
	const files = fs.readFileSync(arg, 'utf8').split('\n').filter(Boolean);
	const [shard, shards] = shardArg ? shardArg.split('/').map(Number) : [0, 1];
	const out = [];
	files.forEach((file, i) => {
		if (i % shards !== shard) return;
		let status = 'ok';
		let hash = '-';
		try {
			const text = run(file);
			if (text === null) status = 'esterror';
			else hash = crypto.createHash('sha1').update(text).digest('hex');
		} catch (e) {
			status = `crash:${String(e && e.message).replace(/\s+/g, ' ').slice(0, 80)}`;
		}
		out.push(`${file}\t${status}\t${hash}`);
	});
	process.stdout.write(out.join('\n') + (out.length ? '\n' : ''));
}
