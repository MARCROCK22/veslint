// Runs the real regexpp 4.12.2 on cases.txt and writes the canonical dump compared against the V port (main.v).
"use strict";
const fs = require("node:fs");
const { RegExpValidator, RegExpParser, RegExpSyntaxError, visitRegExpAST } = require(require("node:path").join(__dirname, "../../build/eval/spider-byte/node_modules/@eslint-community/regexpp"));
const lines = fs.readFileSync(process.argv[2], "utf8").split("\n").filter(Boolean);
const fd = fs.openSync(process.argv[3], "w");
let out = [];
const flush = () => {
	if (out.length) fs.writeSync(fd, out.join("\n") + "\n");
	out = [];
};
const esc = (s) => {
	let o = '"';
	for (let i = 0; i < s.length; i++) {
		const c = s.charCodeAt(i);
		if (c >= 0x20 && c < 0x7f && c !== 0x22 && c !== 0x5c) o += s[i];
		else o += "\\u" + c.toString(16).padStart(4, "0");
	}
	return o + '"';
};
const num = (x) => {
	if (x === Infinity) return "Infinity";
	if (Number.isInteger(x) && Math.abs(x) <= 2 ** 53) return String(x);
	const b = Buffer.alloc(8);
	b.writeDoubleBE(x);
	return "f" + b.toString("hex");
};
const unhex = (h) => {
	let s = "";
	for (let i = 0; i < h.length; i += 4) s += String.fromCharCode(parseInt(h.slice(i, i + 4), 16));
	return s;
};
const res = (f) => {
	try {
		f();
		return "ok";
	} catch (e) {
		if (e instanceof RegExpSyntaxError) return `err ${e.index} ${esc(e.message)}`;
		return "crash";
	}
};
function dumpAst(root) {
	const ids = new Map();
	const order = [];
	const walk = [];
	const handlers = {};
	for (const t of ["Alternative", "Assertion", "Backreference", "CapturingGroup", "Character", "CharacterClass", "CharacterClassRange", "CharacterSet", "ClassIntersection", "ClassStringDisjunction", "ClassSubtraction", "ExpressionCharacterClass", "Flags", "Group", "Modifiers", "ModifierFlags", "Pattern", "Quantifier", "RegExpLiteral", "StringAlternative"]) {
		handlers[`on${t}Enter`] = (n) => {
			if (n.type !== t) throw new Error("handler type mismatch");
			if (!ids.has(n)) {
				ids.set(n, ids.size);
				order.push(n);
			}
			walk.push("+" + ids.get(n));
		};
		handlers[`on${t}Leave`] = (n) => walk.push("-" + ids.get(n));
	}
	visitRegExpAST(root, handlers);
	const val = (v) => {
		if (v === null) return "null";
		if (v === undefined) return "undefined";
		if (typeof v === "boolean") return String(v);
		if (typeof v === "number") return num(v);
		if (typeof v === "string") return esc(v);
		if (Array.isArray(v)) return "[" + v.map(val).join(",") + "]";
		if (typeof v === "object" && typeof v.type === "string") return ids.has(v) ? "#" + ids.get(v) : "#?";
		return "?";
	};
	for (const n of order) {
		const keys = Object.keys(n).sort();
		out.push("N " + keys.map((k) => `${k}=${val(n[k])}`).join(" "));
	}
	out.push("W " + walk.join(""));
}
let lineNo = 0;
for (const line of lines) {
	lineNo++;
	if (out.length > 50000) flush();
	const f = line.split("\t");
	const kind = f[0];
	out.push(`#${lineNo} ${kind}`);
	if (kind === "P") {
		const [, e, st, fl, a, b, h] = f;
		const opts = { ecmaVersion: Number(e), strict: st === "1" };
		const flags = { unicode: fl.includes("u"), unicodeSets: fl.includes("v") };
		const src = unhex(h);
		const start = Number(a);
		const end = Number(b);
		const events = [];
		const v = new RegExpValidator({
			...opts,
			onPatternEnter: (s) => events.push(`P${s}`),
			onPatternLeave: (s, t) => events.push(`Q${s},${t}`),
			onCharacter: (s, t, c) => events.push(`C${s},${t},${num(c)}`),
		});
		out.push("V " + res(() => v.validatePattern(src, start, end, flags)));
		out.push("E " + events.join(" "));
		let ast = null;
		out.push("A " + res(() => (ast = new RegExpParser(opts).parsePattern(src, start, end, flags))));
		if (ast) dumpAst(ast);
	} else if (kind === "F") {
		const [, e, st, a, b, h] = f;
		const opts = { ecmaVersion: Number(e), strict: st === "1" };
		const src = unhex(h);
		out.push("V " + res(() => new RegExpValidator(opts).validateFlags(src, Number(a), Number(b))));
		let ast = null;
		out.push("A " + res(() => (ast = new RegExpParser(opts).parseFlags(src, Number(a), Number(b)))));
		if (ast) dumpAst(ast);
	} else if (kind === "L") {
		const [, e, st, a, b, h] = f;
		const opts = { ecmaVersion: Number(e), strict: st === "1" };
		const src = unhex(h);
		out.push("V " + res(() => new RegExpValidator(opts).validateLiteral(src, Number(a), Number(b))));
		let ast = null;
		out.push("A " + res(() => (ast = new RegExpParser(opts).parseLiteral(src, Number(a), Number(b)))));
		if (ast) dumpAst(ast);
	}
}
flush();
fs.closeSync(fd);
