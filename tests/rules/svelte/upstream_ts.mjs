// node tests/rules/svelte/upstream_ts.mjs [--out DIR] [--check] [svelte/<rule>...]
//
// Writes tests/rules/svelte/<rule>/upstream.ts.json for each rule (without names, the svelte/* rules
// veslint has: the directories with an expected.txt): the cases of its upstream.json as veslint runs
// them, TypeScript only (.claude/SVELTE.md), with what ESLint 10.15.0 and eslint-plugin-svelte 3.24.1
// give for them. tests/upstream_check.py runs these on veslint.
//
// A case is converted the way veslint reads it:
// - a .svelte file (a component) gets lang="ts" on each top-level <script> without a lang (lang="js"
//   and lang="javascript" become "ts"), and svelte-eslint-parser gets typescript-eslint's parser as
//   its one script parser (`parserOptions.parser` by name, not by lang), which veslint's parser
//   imitates: its scripts, its template expressions and a file without a script are TypeScript
//   (upstream parses those with espree, and `lang="typescript"` too). It keeps its file and the
//   program of the fixtures' tsconfig.json (`via: "project"`), as upstream;
// - a JavaScript file that is not a component becomes a TypeScript file (`x.js` -> `x.ts`,
//   `x.svelte.js` -> `x.svelte.ts`), parsed by typescript-eslint's parser (or svelte-eslint-parser
//   with it, a script module): a file that is not on disk, so not in the program (no types).
// Then RuleTester runs the converted case: when it still gives what the upstream test expects, the
// expectation is the test's (`expectation: "upstream"`); when not, it is what ESLint gives on the
// converted case (`expectation: "eslint"`: every problem with its messageId, message, location and
// suggestions, and the output of one pass of fixes, as ESLint's RuleTester makes one).
//
// A case that cannot be converted is listed in `skipped` with the reason: a script whose lang is
// neither JavaScript nor TypeScript, a text with a lone surrogate (a file cannot hold it), a
// configuration with functions (a `_config.cjs`: a veslint configuration is JSON), a case of
// no-conflicting-module-names whose file's extension is its subject, a converted text the parser
// rejects. The cases upstream's requirements leave out (`skip`) are listed too.
//
// The `lints` (comment-directive's, with the svelte/svelte processor) are converted the same way;
// their rules that veslint does not have are left out of their configuration, but no-unused-vars,
// which becomes @typescript-eslint/no-unused-vars (the same rule for TypeScript); their expectation
// is what ESLint gives on the converted lint (messages and output), compared whole.
import fs from 'node:fs';
import path from 'node:path';
import { ROOT, runCase, lintMessages, require } from './eslint_run.mjs';

const RULES_DIR = path.join(ROOT, 'tests/rules/svelte');
const args = process.argv.slice(2);
let out = null;
let check = false;
for (;;) {
  if (args[0] === '--out') {
    // eslint_run.mjs moved to the package's directory: a relative path is the caller's (PWD).
    out = path.resolve(process.env.PWD ?? '.', args[1]);
    args.splice(0, 2);
  } else if (args[0] === '--check') {
    check = true;
    args.splice(0, 1);
  } else break;
}
const rules = args.length
  ? args.map(id => id.replace(/^svelte\//, ''))
  : fs
      .readdirSync(RULES_DIR)
      .filter(entry => fs.existsSync(path.join(RULES_DIR, entry, 'expected.txt')))
      .sort();

// The rules veslint has (rules/rules.v), for the configurations of the lints.
const RULES_V = fs.readFileSync(path.join(ROOT, 'rules/rules.v'), 'utf8');
const ported = new Set([...RULES_V.matchAll(/^pub const \w+ = '([^']+)'$/gm)].map(m => m[1]));
const LINT_RULE_RENAMES = { 'no-unused-vars': '@typescript-eslint/no-unused-vars' };

const { parse: svelteParse } = require('svelte/compiler');
const TS_PARSER = '@typescript-eslint/parser';
const JS_LANGS = new Set(['', 'js', 'javascript']);
const TS_LANGS = new Set(['ts', 'typescript']);

// toTypeScriptComponent adds lang="ts" to the top-level <script> elements of a .svelte text (the
// Svelte compiler finds them): the converted text, or an error naming why it cannot be.
function toTypeScriptComponent(code) {
  let scripts;
  try {
    const ast = svelteParse(code, { modern: true });
    scripts = [ast.module, ast.instance].filter(Boolean).map(s => ({ start: s.start, attributes: s.attributes }));
  } catch {
    scripts = null;
  }
  if (scripts === null) {
    // The compiler's error is the case's (svelte-eslint-parser reports it): the text stays, and its
    // scripts must already be TypeScript, or there must be none, for veslint to lint it.
    const langs = [...code.matchAll(/<script\b([^>]*)>/gi)].map(m => /\blang\s*=\s*["']?([^"'\s>]*)/i.exec(m[1])?.[1] ?? '');
    if (langs.some(lang => !TS_LANGS.has(lang.toLowerCase()))) return { error: 'the Svelte compiler rejects it, and its <script> is not TypeScript' };
    return { code };
  }
  const edits = [];
  for (const script of scripts) {
    const lang = script.attributes.find(a => a.type === 'Attribute' && a.name === 'lang');
    if (!lang) {
      // After `<script`.
      const at = script.start + '<script'.length;
      edits.push([at, at, ' lang="ts"']);
      continue;
    }
    const value = Array.isArray(lang.value) ? lang.value.map(v => v.data ?? '').join('') : lang.value === true ? '' : null;
    if (value === null || (Array.isArray(lang.value) && lang.value.some(v => v.type !== 'Text'))) return { error: 'its <script> has a lang that is not a literal' };
    if (TS_LANGS.has(value.toLowerCase())) continue;
    if (!JS_LANGS.has(value.toLowerCase())) return { error: `its <script> has lang="${value}", which is neither JavaScript nor TypeScript` };
    edits.push([lang.start, lang.end, 'lang="ts"']);
  }
  let text = code;
  for (const [start, end, insert] of edits.sort((a, b) => b[0] - a[0])) text = text.slice(0, start) + insert + text.slice(end);
  return { code: text };
}

// convert gives the converted case (without its expectation) or the reason it cannot be.
function convert(rule, c) {
  if (/[\uD800-\uDBFF](?![\uDC00-\uDFFF])|(?<![\uD800-\uDBFF])[\uDC00-\uDFFF]/.test(c.code)) {
    return { reason: 'the code has a lone surrogate, which a file cannot hold' };
  }
  if (c.configModule) return { reason: 'its configuration has functions (a _config.cjs), which a veslint configuration (JSON) cannot hold' };
  const base = {
    id: c.id,
    kind: c.kind,
    ...(c.name !== undefined && { name: c.name }),
    ...(c.options && { options: c.options }),
    ...(c.settings && { settings: c.settings }),
    languageOptions: { ...c.languageOptions },
  };
  const parserOptions = { ...c.parserOptions, parser: TS_PARSER };
  if (rule === 'no-conflicting-module-names' && !c.file.endsWith('.svelte') && !c.file.endsWith('.ts')) {
    // Its subject is the module's file name (Foo.svelte.js beside Foo.svelte): renaming the file
    // would change the case.
    return { reason: "no-conflicting-module-names' subject is the file's extension, which veslint (TypeScript only) does not lint" };
  }
  if (c.svelte && c.file.endsWith('.svelte')) {
    const converted = toTypeScriptComponent(c.code);
    if (converted.error) return { reason: converted.error };
    return {
      case: {
        ...base,
        code: converted.code,
        file: c.file,
        parser: 'svelte-eslint-parser',
        parserOptions,
        ...(c.via && { via: c.via, tsconfig: c.tsconfig }),
      },
    };
  }
  if (/\.[mc]?jsx?$/.test(c.file)) {
    // A JavaScript file: TypeScript, not on disk (no program).
    const file = c.file.replace(/\.([mc]?)js(x?)$/, '.$1ts$2');
    const parser = c.parser === 'svelte-eslint-parser' ? 'svelte-eslint-parser' : TS_PARSER;
    const options = { ...parserOptions };
    if (parser === TS_PARSER) delete options.parser;
    return { case: { ...base, code: c.code, file, parser, parserOptions: options } };
  }
  return {
    case: {
      ...base,
      code: c.code,
      file: c.file,
      parser: c.parser,
      ...(c.parserOptions && { parserOptions: c.parser === 'svelte-eslint-parser' ? parserOptions : c.parserOptions }),
      ...(c.via && { via: c.via, tsconfig: c.tsconfig }),
    },
  };
}

// applyFixes is ESLint's SourceCodeFixer.applyFixes: the fixes by range, each one that does not
// overlap the ones before.
function applyFixes(code, fixes) {
  const bom = code.startsWith('﻿') ? '﻿' : '';
  const text = code.slice(bom.length);
  let result = bom;
  let last = Number.NEGATIVE_INFINITY;
  for (const fix of [...fixes].sort((a, b) => a.range[0] - b.range[0] || a.range[1] - b.range[1])) {
    const [start, end] = fix.range;
    if (last >= start || start > end) continue;
    if ((start < 0 && end >= 0) || (start === 0 && fix.text.startsWith('﻿'))) result = '';
    result += text.slice(Math.max(0, last), Math.max(0, start)) + fix.text;
    last = end;
  }
  return result + text.slice(Math.max(0, last));
}

// expectationOf is what ESLint gives, as a case's errors and output.
function expectationOf(code, messages) {
  const errors = messages.map(m => {
    const e = { messageId: m.messageId, message: m.message, line: m.line, column: m.column };
    if (m.endLine !== undefined) Object.assign(e, { endLine: m.endLine, endColumn: m.endColumn });
    if (m.suggestions) {
      e.suggestions = m.suggestions.map(s => ({ messageId: s.messageId, desc: s.desc, output: applyFixes(code, [s.fix]) }));
    }
    return e;
  });
  const fixes = messages.filter(m => m.fix).map(m => m.fix);
  return { errors, output: fixes.length ? applyFixes(code, fixes) : null };
}

// convertLint converts a lint of an `it` block: its text, its parser, and the rules veslint has.
function convertLint(lint) {
  const converted = toTypeScriptComponent(lint.code);
  if (converted.error) return { reason: converted.error };
  const config = structuredClone(lint.config);
  config.languageOptions = { ...config.languageOptions, parserOptions: { ...config.languageOptions?.parserOptions, parser: TS_PARSER } };
  const lintRules = {};
  for (const [rule, value] of Object.entries(config.rules ?? {})) {
    const name = LINT_RULE_RENAMES[rule] ?? rule;
    if (ported.has(name)) lintRules[name] = value;
  }
  config.rules = lintRules;
  if (Object.keys(lintRules).some(rule => rule.startsWith('@typescript-eslint/'))) {
    config.plugins = { ...config.plugins, '@typescript-eslint': '@typescript-eslint/eslint-plugin' };
  }
  return { lint: { id: lint.id, name: lint.name, api: lint.api, config, code: converted.code, filename: lint.filename, ...(lint.fix && { fix: lint.fix }) } };
}

let stale = false;
let total = 0;
let kept = 0;
let fromEslint = 0;
let skippedTotal = 0;
for (const rule of rules) {
  const data = JSON.parse(fs.readFileSync(path.join(RULES_DIR, rule, 'upstream.json'), 'utf8'));
  const cases = [];
  const results = [];
  const skipped = [];
  const counts = { upstream: 0, eslint: 0 };
  for (const c of data.cases) {
    if (c.skip) {
      skipped.push({ id: c.id, reason: "upstream's requirements leave it out" });
      continue;
    }
    const conv = convert(rule, c);
    if (conv.reason) {
      skipped.push({ id: c.id, reason: conv.reason });
      continue;
    }
    const item = { ...conv.case };
    if (c.kind === 'invalid') {
      item.errors = c.errors;
      if ('output' in c) item.output = c.output;
    }
    const { failure, messages } = runCase(rule, item, data.languageOptions);
    if (messages && !messages.some(m => m.fatal)) results.push({ filePath: c.id, messages });
    if (!failure) {
      cases.push({ ...item, expectation: 'upstream' });
      counts.upstream++;
      continue;
    }
    if (!messages) {
      skipped.push({ id: c.id, reason: `RuleTester fails before it lints the converted case: ${failure.message.split('\n')[0]}` });
      continue;
    }
    const fatal = messages.find(m => m.fatal);
    if (fatal) {
      skipped.push({ id: c.id, reason: `the parser rejects the converted case: ${fatal.message}` });
      continue;
    }
    const { errors, output } = expectationOf(item.code, messages);
    const { errors: _errors, output: _output, ...rest } = item;
    cases.push({ ...rest, kind: errors.length ? 'invalid' : 'valid', ...(errors.length && { errors }), output, expectation: 'eslint' });
    counts.eslint++;
  }
  const lints = [];
  for (const lint of data.lints ?? []) {
    const conv = convertLint(lint);
    if (conv.reason) {
      skipped.push({ id: lint.id, reason: conv.reason });
      continue;
    }
    const { messages, output } = await lintMessages(conv.lint);
    if (messages.some(m => m.fatal)) {
      skipped.push({ id: lint.id, reason: `the parser rejects the converted lint: ${messages.find(m => m.fatal).message}` });
      continue;
    }
    lints.push({ ...conv.lint, messages, ...(output !== undefined && { output }) });
  }
  const header = {
    rule: data.rule,
    upstream: data.upstream,
    files: data.files,
    messages: data.messages,
    ...(data.languageOptions && { languageOptions: data.languageOptions }),
    generator: 'tests/rules/svelte/upstream_ts.mjs',
  };
  const text =
    JSON.stringify(header).slice(0, -1) +
    `,"cases":[\n${cases.map(c => JSON.stringify(c)).join(',\n')}\n],"lints":[\n${lints.map(l => JSON.stringify(l)).join(',\n')}\n],"skipped":[\n${skipped.map(s => JSON.stringify(s)).join(',\n')}\n]}\n`;
  const file = path.join(RULES_DIR, rule, 'upstream.ts.json');
  if (check) {
    if (!fs.existsSync(file) || fs.readFileSync(file, 'utf8') !== text) {
      console.log(`FAIL   svelte/${rule}: tests/rules/svelte/${rule}/upstream.ts.json is not what ESLint gives now (run node tests/rules/svelte/upstream_ts.mjs svelte/${rule})`);
      stale = true;
    }
  } else {
    fs.writeFileSync(file, text);
  }
  if (out) {
    fs.mkdirSync(path.join(out, 'svelte'), { recursive: true });
    fs.writeFileSync(path.join(out, 'svelte', `${rule}.json`), JSON.stringify(results));
  }
  total += data.cases.length + (data.lints?.length ?? 0);
  kept += counts.upstream;
  fromEslint += counts.eslint;
  skippedTotal += skipped.length;
  console.log(
    `svelte/${rule}: ${data.cases.length} cases${data.lints?.length ? ` and ${data.lints.length} lints` : ''}: ${counts.upstream} expect what their test expects, ${counts.eslint} what ESLint gives on the converted case${lints.length ? `, ${lints.length} lints` : ''}, ${skipped.length} not convertible`,
  );
}
console.log(`${total} cases: ${kept} with their test's expectation, ${fromEslint} with ESLint's on the converted case, ${skippedTotal} not convertible`);
process.exit(stale ? 1 : 0);
