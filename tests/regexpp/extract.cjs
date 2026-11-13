// Collects every regex literal (pattern + flags), every string passed to RegExp/new RegExp, and every other string
// literal of the code of the ESLint test cases of the nine regex rules. Writes JSON {patterns:[], flags:[]}.
"use strict";
const Module = require("node:module");
const path = require("node:path");
const fs = require("node:fs");
const ROOT = path.join(__dirname, "../..");
const NM = path.join(ROOT, "build/eval/spider-byte/node_modules");
const acorn = require(path.join(NM, "acorn"));
acorn.Parser.prototype.validateRegExpFlags = function () {};
acorn.Parser.prototype.validateRegExpPattern = function () {};
const walk = (node, cb) => {
	if (!node || typeof node.type !== "string") return;
	cb(node);
	for (const k of Object.keys(node)) {
		if (k === "parent") continue;
		const v = node[k];
		if (Array.isArray(v)) v.forEach((x) => x && typeof x === "object" && walk(x, cb));
		else if (v && typeof v === "object" && typeof v.type === "string") walk(v, cb);
	}
};
const collected = [];
class FakeRuleTester {
	constructor() {}
	run(name, rule, tests) {
		for (const t of [...(tests.valid || []), ...(tests.invalid || [])]) {
			if (typeof t === "string") collected.push(t);
			else if (t && typeof t === "object") {
				if (typeof t.code === "string") collected.push(t.code);
				if (typeof t.output === "string") collected.push(t.output);
				for (const e of t.errors || []) {
					for (const s of (e && e.suggestions) || []) if (typeof s.output === "string") collected.push(s.output);
				}
			}
		}
	}
	static only(x) {
		return x;
	}
}
const origLoad = Module._load;
Module._load = function (request, parent, isMain) {
	if (request.startsWith("../../../lib/rule-tester")) return FakeRuleTester;
	if (request.startsWith("../../../lib/rules/")) return {};
	return origLoad.call(this, request, parent, isMain);
};
const rules = ["no-control-regex", "no-div-regex", "no-empty-character-class", "no-invalid-regexp", "no-misleading-character-class", "no-regex-spaces", "no-useless-backreference", "no-useless-escape", "prefer-regex-literals"];
for (const r of rules) require(path.join(ROOT, `build/upstream/eslint/tests/lib/rules/${r}.js`));
const patterns = new Set();
const flags = new Set();
let parseFailures = 0;
for (const code of collected) {
	let ast = null;
	for (const sourceType of ["module", "script"]) {
		try {
			ast = acorn.parse(code, { ecmaVersion: "latest", sourceType, allowReturnOutsideFunction: true, allowHashBang: true });
			break;
		} catch {}
	}
	if (!ast) {
		parseFailures++;
		if (process.env.SHOW_FAIL) process.stderr.write(JSON.stringify(code) + "\n");
		continue;
	}
	walk(ast, (n) => {
		if (n.type === "Literal" && n.regex) {
			patterns.add(n.regex.pattern);
			flags.add(n.regex.flags);
		} else if (n.type === "Literal" && typeof n.value === "string") {
			patterns.add(n.value);
			if (n.value.length < 12) flags.add(n.value);
		} else if (n.type === "TemplateLiteral") {
			for (const q of n.quasis) if (typeof q.value.cooked === "string") patterns.add(q.value.cooked);
		}
	});
}
process.stderr.write(`test codes: ${collected.length}, unparsable: ${parseFailures}, patterns: ${patterns.size}, flags: ${flags.size}\n`);
fs.writeFileSync(process.argv[2], JSON.stringify({ patterns: [...patterns], flags: [...flags] }));
