// Builds the differential test inputs: corpus patterns (from extract.cjs) plus generated ones.
// Usage: node cases.mjs corpus.json N_GENERATED SEED out.txt [classes]
// Line formats (tab separated, sources as 4-hex-digit UTF-16 units):
//   P ecma strict flags(-|u|v|uv) start end source
//   F ecma strict start end source
//   L ecma strict start end source
import fs from "node:fs";
const [corpusPath, nGen, seedArg, outPath, MODE = ""] = process.argv.slice(2);
const corpus = JSON.parse(fs.readFileSync(corpusPath, "utf8"));
let seed = Number(seedArg) >>> 0;
function rnd() {
	seed = (seed + 0x6d2b79f5) >>> 0;
	let t = seed;
	t = Math.imul(t ^ (t >>> 15), t | 1);
	t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
	return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
}
const pick = (a) => a[Math.floor(rnd() * a.length)];
const names = ["a", "b", "$", "_x", "\\u0061", "\\u{61}", "\u{1d49c}", "\\ud835\\udc9c", "a‌", "1", "a-", "", "\\u{1d49c}"];
const atoms = ["a", "b", "x", "Z", "0", "7", "9", " ", "  ", "-", ",", ":", "=", "!", "<", ">", "'", '"', "&", "&&", "--", "!!", "##", "~~", "}", "]", "{", "/", "é", "‌", "\n", " ", "\t", "\u0001", "\u001f", "\u{1f600}", "\ud83d", "\ude00", "\ud83d\ud83d", ".", "^", "$", "|", "\\"];
const escapes = ["\\d", "\\D", "\\w", "\\W", "\\s", "\\S", "\\b", "\\B", "\\u0041", "\\u{1F600}", "\\u{110000}", "\\u{0}", "\\u{}", "\\u{00000000041}", "\\u{FFFFFFFFFFFF}", "\\uD83D\\uDE00", "\\uD83D", "\\uDE00", "\\uD83D\\u0041", "\\u12", "\\u", "\\x41", "\\x1f", "\\x4", "\\x", "\\c", "\\cA", "\\cz", "\\c1", "\\c_", "\\c*", "\\0", "\\00", "\\012", "\\377", "\\400", "\\08", "\\8", "\\9", "\\1", "\\2", "\\3", "\\10", "\\99999999999999999999", "\\k<a>", "\\k<b>", "\\k<$>", "\\k", "\\k<", "\\k<a", "\\k<1>", "\\p{L}", "\\P{L}", "\\p{Lu}", "\\p{Script=Greek}", "\\p{sc=Grek}", "\\p{scx=Kawi}", "\\p{Script=Berf}", "\\p{sc=Toto}", "\\p{sc=Dogr}", "\\p{sc=Elym}", "\\p{sc=Chrs}", "\\p{gc=Lu}", "\\p{General_Category=Letter}", "\\p{gc=Greek}", "\\p{RGI_Emoji}", "\\P{RGI_Emoji}", "\\p{Basic_Emoji}", "\\p{Foo}", "\\p{", "\\p", "\\p{}", "\\p{=}", "\\p{L=}", "\\p{ASCII}", "\\p{Extended_Pictographic}", "\\p{EBase}", "\\p{Any}", "\\p{Script=Unknown}", "\\p{digit}", "\\p{cntrl}", "\\p{Script_Extensions=Latin}", "\\p{Lowercase", "\\q{abc|d}", "\\q{}", "\\q{a", "\\q{a|}", "\\q{\\q{a}}", "\\q", "\\/", "\\-", "\\&", "\\!", "\\]", "\\[", "\\(", "\\)", "\\.", "\\*", "\\a", "\\z", "\\_", "\\$", "\\ü", "\\\u{1f600}", "\\\ud83d", "\\ ", "\\|", "\\{", "\\}", "\\^", "\\,", "\\~", "\\#", "\\%", "\\`", "\\@", "\\=", "\\<", "\\>", "\;", "\\:", "\\'", "\\n", "\\t", "\\r", "\\f", "\\v", "\\e", "\\\\", "\\\n"];
const quants = ["*", "+", "?", "*?", "+?", "??", "{2}", "{2,}", "{2,3}", "{3,2}", "{,3}", "{", "}", "{2", "{2,", "{a}", "{99999999999999999999}", "{1,99999999999999999999}", "{2}?", "{0}", "{0,0}", "**", "{1}{2}"];
const modifiers = ["(?i:", "(?-i:", "(?i-m:", "(?ims:", "(?ii:", "(?i-i:", "(?-:", "(?m-:", "(?-s:", "(?x:", "(?i", "(?-", "(?i-ms:", "(?s-im:", "(?-mm:", "(?I:"];
function gen(depth) {
	let s = "";
	const n = Math.floor(rnd() * (depth > 2 ? 3 : 6));
	for (let i = 0; i < n; i++) s += term(depth);
	if (rnd() < 0.15) s += "|" + gen(depth + 1);
	return s;
}
function group(depth) {
	const inner = depth > 4 ? pick(atoms) : gen(depth + 1);
	const r = rnd();
	let open;
	if (r < 0.2) open = "(";
	else if (r < 0.3) open = "(?:";
	else if (r < 0.5) open = `(?<${pick(names)}>`;
	else if (r < 0.58) open = pick(["(?=", "(?!", "(?<=", "(?<!"]);
	else if (r < 0.7) open = pick(modifiers);
	else open = pick(["(?", "(?<", "(?<a", "(?<=a", "(?P<a>", "(?<a>", "(?<b>", "(?<a>"]);
	return open + inner + (rnd() < 0.93 ? ")" : "");
}
function classAtom() {
	const r = rnd();
	if (r < 0.4) return pick(atoms);
	if (r < 0.7) return pick(escapes);
	if (r < 0.85) return pick(atoms) + "-" + pick(atoms);
	return pick(["\\b", "\\-", "\\c1", "\\c_", "\\c", "\\q{ab|c}", "\\q{a}", "\\q{}", "a-z", "z-a", "\\d-a", "a-\\d", "\\u{1F600}-\\u{1F601}", "&&", "--", "[", "]", "(", ")", "/", "|", "{", "}"]);
}
function cls(depth) {
	let s = rnd() < 0.25 ? "[^" : "[";
	const r = rnd();
	const n = Math.floor(rnd() * 4);
	if (r < 0.2 && depth < 4) {
		// set operation
		const op = rnd() < 0.5 ? "&&" : "--";
		const k = 2 + Math.floor(rnd() * 2);
		const parts = [];
		for (let i = 0; i < k; i++) parts.push(rnd() < 0.4 ? cls(depth + 1) : classAtom());
		s += parts.join(rnd() < 0.85 ? op : pick(["&&", "--", "&&&", "-", "&"]));
	} else {
		for (let i = 0; i < n; i++) s += rnd() < 0.15 && depth < 4 ? cls(depth + 1) : classAtom();
	}
	return s + (rnd() < 0.92 ? "]" : "");
}
function term(depth) {
	const r = rnd();
	let t;
	if (MODE === "classes" && rnd() < 0.6) return cls(depth) + (rnd() < 0.1 ? pick(quants) : "");
	if (r < 0.3) t = pick(atoms);
	else if (r < 0.55) t = pick(escapes);
	else if (r < 0.72) t = depth > 5 ? pick(atoms) : group(depth);
	else if (r < 0.9) t = cls(depth);
	else t = pick(["^", "$", "\\b", "\\B", ")", "(", "[", "]", "{", "}", "|", "\\"]);
	if (rnd() < 0.25) t += pick(quants);
	return t;
}
const generated = new Set();
let guard = 0;
while (generated.size < Number(nGen) && guard++ < Number(nGen) * 20) generated.add(gen(0));
const patterns = [...new Set([...corpus.patterns, ...generated])];
const flagStrs = new Set(corpus.flags);
for (const f of ["", "u", "v", "uv", "gimsuyd", "gimsuydv", "gg", "ii", "x", "U", "é", "\ud83d", "dgimsuy", "yu", "vu", "d", "s", "y", "gu", "iv", "iu ", " "]) flagStrs.add(f);
for (let i = 0; i < 300; i++) {
	let f = "";
	const n = Math.floor(rnd() * 5);
	for (let j = 0; j < n; j++) f += pick("gimsuydvgimsuydvxZ".split(""));
	flagStrs.add(f);
}
const hex = (s) => {
	let o = "";
	for (let i = 0; i < s.length; i++) o += s.charCodeAt(i).toString(16).padStart(4, "0");
	return o;
};
const ECMAS = [5, 2015, 2018, 2020, 2022, 2024, 2025];
const out = [];
for (const p of patterns) {
	const h = hex(p);
	for (const e of ECMAS) for (const f of ["-", "u", "v", "uv"]) out.push(`P\t${e}\t0\t${f}\t0\t${p.length}\t${h}`);
	for (const e of [2018, 2025]) for (const f of ["-", "u", "v", "uv"]) out.push(`P\t${e}\t1\t${f}\t0\t${p.length}\t${h}`);
	const wrapped = hex("\ud83d" + p + "\ude00x");
	for (const f of ["-", "u"]) out.push(`P\t2025\t0\t${f}\t1\t${p.length + 1}\t${wrapped}`);
	for (const f of ["", "u", "v", "gimsuyd", "uv"]) {
		const lit = "/" + p + "/" + f;
		out.push(`L\t2025\t0\t0\t${lit.length}\t${hex(lit)}`);
	}
	const lit = "/" + p + "/";
	out.push(`L\t2015\t0\t0\t${lit.length}\t${hex(lit)}`);
	out.push(`L\t2025\t1\t0\t${lit.length}\t${hex(lit)}`);
	out.push(`L\t2025\t0\t0\t${p.length}\t${h}`);
}
for (const f of flagStrs) for (const e of ECMAS) out.push(`F\t${e}\t0\t0\t${f.length}\t${hex(f)}`);
// literal start/end inside a bigger source
for (const p of patterns.slice(0, 500)) {
	const src = "x=/" + p + "/gu;";
	out.push(`L\t2025\t0\t2\t${src.length - 1}\t${hex(src)}`);
}
fs.writeFileSync(outPath, out.join("\n") + "\n");
process.stderr.write(`patterns: ${patterns.length} (generated ${generated.size}), flag strings: ${flagStrs.size}, cases: ${out.length}\n`);
