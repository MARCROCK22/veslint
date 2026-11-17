// node tests/rules/vue/upstream_ts.mjs [vue/<rule>...]
//
// Writes tests/rules/vue/<rule>/upstream.ts.json for each rule (without names, the vue/* rules veslint
// has: the directories with an expected.txt): the cases of its upstream.json as veslint runs them,
// TypeScript only (.claude/VUE.md), with what ESLint 10.15.0 and eslint-plugin-vue 10.12.1 give for
// them. tests/upstream_check.py runs these on veslint.
//
// A case is converted the way veslint reads it:
// - a .vue file (an SFC) gets lang="ts" on each top-level <script> without a lang (lang="js" becomes
//   "ts", lang="jsx" "tsx"), and vue-eslint-parser gets typescript-eslint's parser for its scripts
//   and template expressions, which veslint's parser imitates (also when the script was already
//   TypeScript, or when there is no script: upstream parses template expressions with espree);
// - a file that is not a .vue becomes a TypeScript file (test.ts; .tsx with JSX) parsed by
//   typescript-eslint's parser, which is how a Vue project lints its .ts files;
// - a .vue file named by the case is kept; a case without a file name gets test.vue (or test.ts).
// Then RuleTester runs the converted case: when it still gives what the upstream test expects, the
// expectation is the test's (`expectation: "upstream"`); when not, it is what ESLint gives on the
// converted case (`expectation: "eslint"`: every problem with its messageId, message, location and
// suggestions, and the output of one pass of fixes, as ESLint's RuleTester makes one).
//
// A case that cannot be converted is listed in `skipped` with the reason: veslint lints every .vue
// file as an SFC (a .vue read as a script by espree or typescript-eslint's parser is not one), a
// script whose lang is not JavaScript or TypeScript, a text with a lone surrogate (a file cannot
// hold it), a converted text typescript-eslint's parser rejects.
//
// The `lints` (comment-directive's, with the vue/vue processor) are converted the same way; their
// rules that veslint does not have are left out of their configuration, but no-unused-vars, which
// becomes @typescript-eslint/no-unused-vars (the same rule for TypeScript); their expectation is
// what ESLint gives on the converted lint (messages and output), compared whole.
import fs from 'node:fs';
import path from 'node:path';
import { ROOT, runCase, lintMessages, clearCaches, testFileOf, require } from './eslint_run.mjs';

const RULES_DIR = path.join(ROOT, 'tests/rules/vue');
const args = process.argv.slice(2);
// --out DIR: ESLint's problems on each converted case also go to DIR/vue/<rule>.json, with the case's
// id as the file path (for tests/upstream_compare.py, as tests/rules/vue/upstream_eslint.mjs does).
// --check: upstream.ts.json is not written; the exit code is 1 when it is not what it would be.
let out = null;
let check = false;
for (;;) {
  if (args[0] === '--out') {
    // eslint_run.mjs moved to the clone's root: a relative path is the caller's (PWD).
    out = path.resolve(process.env.PWD ?? '.', args[1]);
    args.splice(0, 2);
  } else if (args[0] === '--check') {
    check = true;
    args.splice(0, 1);
  } else break;
}
const rules = args.length
  ? args.map(id => id.replace(/^vue\//, ''))
  : fs
      .readdirSync(RULES_DIR)
      .filter(entry => fs.existsSync(path.join(RULES_DIR, entry, 'expected.txt')))
      .sort();

// The rules veslint has (rules/rules.v), for the configurations of the lints.
const RULES_V = fs.readFileSync(path.join(ROOT, 'rules/rules.v'), 'utf8');
const ported = new Set([...RULES_V.matchAll(/^pub const \w+ = '([^']+)'$/gm)].map(m => m[1]));
const LINT_RULE_RENAMES = { 'no-unused-vars': '@typescript-eslint/no-unused-vars' };

const vueParser = require('vue-eslint-parser');

// toTypeScriptSfc adds lang="ts" to the top-level <script> elements of a .vue text (vue-eslint-parser
// finds them, without parsing them): the converted text, or an error naming why it cannot be.
function toTypeScriptSfc(code) {
  const { services } = vueParser.parseForESLint(code, { parser: false, filePath: 'test.vue', ecmaVersion: 'latest', sourceType: 'module' });
  const scripts = services.getDocumentFragment().children.filter(node => node.type === 'VElement' && node.name === 'script');
  const edits = [];
  for (const script of scripts) {
    const lang = script.startTag.attributes.find(a => !a.directive && a.key.name === 'lang');
    if (!lang) {
      // After `<script`, whatever its case.
      const at = script.startTag.range[0] + 1 + script.rawName.length;
      edits.push([at, at, ' lang="ts"']);
      continue;
    }
    const value = lang.value?.value ?? '';
    const replacement = { js: 'ts', jsx: 'tsx', '': 'ts' }[value.toLowerCase()];
    if (value === 'ts' || value === 'tsx') continue;
    if (!replacement) return { error: `its <script> has lang="${value}", which is neither JavaScript nor TypeScript` };
    // The whole attribute: `lang`, `lang=""`, `lang=js`, `lang='js'`.
    edits.push([lang.range[0], lang.range[1], `lang="${replacement}"`]);
  }
  let out = code;
  for (const [start, end, text] of edits.sort((a, b) => b[0] - a[0])) out = out.slice(0, start) + text + out.slice(end);
  return { code: out };
}

const TS_PARSER = '@typescript-eslint/parser';

// convert gives the converted case (without its expectation) or the reason it cannot be.
function convert(c) {
  if (/[\uD800-\uDBFF](?![\uDC00-\uDFFF])|(?<![\uD800-\uDBFF])[\uDC00-\uDFFF]/.test(c.code)) {
    return { reason: 'the code has a lone surrogate, which a file cannot hold' };
  }
  const base = {
    id: c.id,
    kind: c.kind,
    ...(c.name !== undefined && { name: c.name }),
    ...(c.options && { options: c.options }),
    ...(c.settings && { settings: c.settings }),
    ...(c.plugins && { plugins: c.plugins }),
    ...(c.rule && { rule: c.rule }),
    languageOptions: { ...c.languageOptions },
  };
  const filename = c.filename;
  if (c.sfc) {
    const converted = toTypeScriptSfc(c.code);
    if (converted.error) return { reason: converted.error };
    const parserOptions = { ...c.parserOptions, parser: c.via === 'project' ? { ts: TS_PARSER } : TS_PARSER };
    const file = c.via === 'project' ? c.file : filename && path.extname(filename) === '.vue' ? filename : 'test.vue';
    return {
      case: {
        ...base,
        code: converted.code,
        filename: file,
        parser: 'vue-eslint-parser',
        parserOptions,
        ...(c.via && { via: c.via, file: c.file, tsconfig: c.tsconfig }),
      },
      converted: converted.code !== c.code,
    };
  }
  if (filename && path.extname(filename) === '.vue') {
    return { reason: `ESLint reads this .vue file as a script (${c.parser}), veslint reads every .vue file as an SFC` };
  }
  const jsx = c.script === 'jsx' || c.script === 'tsx' || /\.[jt]sx$/.test(filename ?? '') || c.languageOptions?.parserOptions?.ecmaFeatures?.jsx || c.parserOptions?.ecmaFeatures?.jsx;
  const file = filename ? filename.replace(/\.[mc]?[jt]sx?$|$/, jsx ? '.tsx' : '.ts') : jsx ? 'test.tsx' : 'test.ts';
  const parserOptions = { ...c.parserOptions };
  delete parserOptions.parser;
  if (jsx) parserOptions.ecmaFeatures = { ...parserOptions.ecmaFeatures, jsx: true };
  return {
    case: { ...base, code: c.code, filename: file, parser: TS_PARSER, ...(Object.keys(parserOptions).length && { parserOptions }) },
    converted: true,
  };
}

// applyFixes is ESLint's SourceCodeFixer.applyFixes: the fixes by range, each one that does not
// overlap the ones before.
function applyFixes(code, fixes) {
  const bom = code.startsWith('﻿') ? '﻿' : '';
  const text = code.slice(bom.length);
  let out = bom;
  let last = Number.NEGATIVE_INFINITY;
  for (const fix of [...fixes].sort((a, b) => a.range[0] - b.range[0] || a.range[1] - b.range[1])) {
    const [start, end] = fix.range;
    if (last >= start || start > end) continue;
    if ((start < 0 && end >= 0) || (start === 0 && fix.text.startsWith('﻿'))) out = '';
    out += text.slice(Math.max(0, last), Math.max(0, start)) + fix.text;
    last = end;
  }
  return out + text.slice(Math.max(0, last));
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
  const converted = toTypeScriptSfc(lint.code);
  if (converted.error) return { reason: converted.error };
  const config = structuredClone(lint.config);
  config.languageOptions = { ...config.languageOptions, parserOptions: { ...config.languageOptions?.parserOptions, parser: TS_PARSER } };
  const rules = {};
  for (const [rule, value] of Object.entries(config.rules ?? {})) {
    const name = LINT_RULE_RENAMES[rule] ?? rule;
    if (ported.has(name)) rules[name] = value;
  }
  config.rules = rules;
  if (Object.keys(rules).some(rule => rule.startsWith('@typescript-eslint/'))) {
    config.plugins = { ...config.plugins, '@typescript-eslint': '@typescript-eslint/eslint-plugin' };
  }
  return { lint: { id: lint.id, name: lint.name, api: lint.api, config, code: converted.code, filename: lint.filename, ...(lint.fix && { fix: lint.fix }) } };
}

let stale = false;
let total = 0;
let kept = 0;
let fromEslint = 0;
let skippedTotal = 0;
let lastTestFile = null;
for (const rule of rules) {
  const data = JSON.parse(fs.readFileSync(path.join(RULES_DIR, rule, 'upstream.json'), 'utf8'));
  const cases = [];
  const results = [];
  const skipped = [];
  const counts = { upstream: 0, eslint: 0 };
  for (const c of data.cases) {
    const testFile = testFileOf(c.id);
    if (testFile !== lastTestFile) {
      clearCaches();
      lastTestFile = testFile;
    }
    const conv = convert(c);
    if (conv.reason) {
      skipped.push({ id: c.id, reason: conv.reason });
      continue;
    }
    const item = { ...conv.case };
    if (c.kind === 'invalid') {
      item.errors = c.errors;
      if ('output' in c) item.output = c.output;
    }
    const { failure, messages } = runCase(rule, item);
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
      skipped.push({ id: c.id, reason: `typescript-eslint's parser rejects the converted case: ${fatal.message}` });
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
      skipped.push({ id: lint.id, reason: `typescript-eslint's parser rejects the converted lint: ${messages.find(m => m.fatal).message}` });
      continue;
    }
    lints.push({ ...conv.lint, messages, ...(output !== undefined && { output }) });
  }
  const header = { rule: data.rule, upstream: data.upstream, files: data.files, messages: data.messages, generator: 'tests/rules/vue/upstream_ts.mjs' };
  const text =
    JSON.stringify(header).slice(0, -1) +
    `,"cases":[\n${cases.map(c => JSON.stringify(c)).join(',\n')}\n],"lints":[\n${lints.map(l => JSON.stringify(l)).join(',\n')}\n],"skipped":[\n${skipped.map(s => JSON.stringify(s)).join(',\n')}\n]}\n`;
  const file = path.join(RULES_DIR, rule, 'upstream.ts.json');
  if (check) {
    if (!fs.existsSync(file) || fs.readFileSync(file, 'utf8') !== text) {
      console.log(`FAIL   vue/${rule}: tests/rules/vue/${rule}/upstream.ts.json is not what ESLint gives now (run node tests/rules/vue/upstream_ts.mjs vue/${rule})`);
      stale = true;
    }
  } else {
    fs.writeFileSync(file, text);
  }
  if (out) {
    fs.mkdirSync(path.join(out, 'vue'), { recursive: true });
    fs.writeFileSync(path.join(out, 'vue', `${rule}.json`), JSON.stringify(results));
  }
  total += data.cases.length + (data.lints?.length ?? 0);
  kept += counts.upstream;
  fromEslint += counts.eslint;
  skippedTotal += skipped.length;
  console.log(
    `vue/${rule}: ${data.cases.length} cases${data.lints?.length ? ` and ${data.lints.length} lints` : ''}: ${counts.upstream} expect what their test expects, ${counts.eslint} what ESLint gives on the converted case${lints.length ? `, ${lints.length} lints` : ''}, ${skipped.length} not convertible`,
  );
}
console.log(`${total} cases: ${kept} with their test's expectation, ${fromEslint} with ESLint's on the converted case, ${skippedTotal} not convertible`);
process.exit(stale ? 1 : 0);
