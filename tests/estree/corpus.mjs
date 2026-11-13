// Builds the corpus of the differential test: a list of absolute paths, one per line, without
// duplicate contents. The `code` of every upstream.json case is written to corpus/up/<hash>.ts
// (or .tsx when its "file" ends in .tsx).
// Usage: node gen_corpus.mjs <veslint root> <out dir>
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';

const [root, outDir] = process.argv.slice(2);
const upDir = path.join(outDir, 'up');
fs.mkdirSync(upDir, { recursive: true });

function walk(dir, pred, out) {
	if (!fs.existsSync(dir)) return;
	for (const ent of fs.readdirSync(dir, { withFileTypes: true })) {
		const p = path.join(dir, ent.name);
		if (ent.isDirectory()) {
			if (ent.name === 'node_modules') continue;
			walk(p, pred, out);
		} else if (ent.isFile() && pred(p)) {
			out.push(p);
		}
	}
}

const isTs = p => /\.(ts|tsx|mts|cts)$/.test(p);
const seen = new Set();
const groups = { rules: [], upstream: [], scope: [], eval: [] };
function add(group, file) {
	const text = fs.readFileSync(file);
	const key = crypto.createHash('sha1').update(text).update(path.extname(file) === '.tsx' ? 'x' : 't').digest('hex');
	if (seen.has(key)) return;
	seen.add(key);
	groups[group].push(file);
}

const ruleFiles = [];
walk(path.join(root, 'tests/rules'), isTs, ruleFiles);
ruleFiles.sort().forEach(f => add('rules', f));

const upstreamJsons = [];
walk(path.join(root, 'tests/rules'), p => path.basename(p) === 'upstream.json', upstreamJsons);
for (const f of upstreamJsons.sort()) {
	const data = JSON.parse(fs.readFileSync(f, 'utf8'));
	for (const c of data.cases ?? []) {
		if (typeof c.code !== 'string') continue;
		const tsx = typeof c.file === 'string' && c.file.endsWith('.tsx');
		const hash = crypto.createHash('sha1').update(c.code).update(tsx ? 'x' : 't').digest('hex').slice(0, 16);
		const p = path.join(upDir, `${hash}${tsx ? '.tsx' : '.ts'}`);
		if (!fs.existsSync(p)) fs.writeFileSync(p, c.code);
		add('upstream', p);
	}
}

const scopeFiles = [];
walk(path.join(root, 'tests/scope'), isTs, scopeFiles);
scopeFiles.sort().forEach(f => add('scope', f));

const evalDir = path.join(root, 'build/eval');
if (fs.existsSync(evalDir)) {
	for (const project of fs.readdirSync(evalDir).sort()) {
		const files = [];
		walk(path.join(evalDir, project, 'src'), isTs, files);
		files.sort().forEach(f => add('eval', f));
	}
}

const all = [];
for (const [group, files] of Object.entries(groups)) {
	fs.writeFileSync(path.join(outDir, `${group}.txt`), files.join('\n') + '\n');
	all.push(...files);
	console.log(`${group}: ${files.length}`);
}
fs.writeFileSync(path.join(outDir, 'list.txt'), all.join('\n') + '\n');
console.log(`total: ${all.length}`);
