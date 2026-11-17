// node tests/rules/vue/upstream_eslint.mjs [--out DIR] [vue/<rule>...]
//
// Runs the cases of tests/rules/vue/<rule>/upstream.json (every rule without names) with ESLint
// 10.15.0 and the published eslint-plugin-vue 10.12.1 of build/upstream/vue-deps, through ESLint's
// own RuleTester, as the upstream tests run them (tests/eslint-compat.ts hands them that class):
// each case is given back its parsers (vue-eslint-parser, typescript-eslint's parser, espree), its
// parserOptions, languageOptions, settings and plugins, and RuleTester checks it as upstream does
// (the problems, their messages, locations and suggestions, the output of one pass of fixes, no
// fatal error, no change to the AST). Each case runs alone: a failure is that case's. It shows that
// upstream.json holds the upstream tests faithfully.
//
// The cases run where upstream's run: in the clone's root, build/upstream/vue (`<cwd>` in a case),
// with the clone's `dist` (the published build) and the node_modules tools/gen_upstream_cases.mjs
// makes there (tests/upstream/README.md); the typed ones lint src/test.vue of the directory
// tests/upstream/vue/setup.sh makes (a copy of the clone's tests/fixtures/typescript, with vue) in a
// temporary directory, with the program of its tsconfig.json, the parser's caches cleared between
// test files as each runs in a process of its own upstream. The `lints` (the `it` blocks that lint with ESLint or Linter) are
// linted again: ESLint must give the problems (and the output) recorded there.
//
// --out DIR writes DIR/vue/<rule>.json, ESLint's problems for each case with its id as the file path,
// as tests/rules/upstream_eslint.mjs does. Exit code 1 when a case does not give what its test
// expects (unless tests/upstream/vue/known.txt lists it), or a case listed there passes.
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { execFileSync } from 'node:child_process';
import { createRequire } from 'node:module';

const ROOT = path.resolve(import.meta.dirname, '../../..');
const VUE = path.join(ROOT, 'build/upstream/vue');
const NM = path.join(ROOT, 'build/upstream/vue-deps/node_modules');
for (const needed of [NM, path.join(VUE, 'dist'), path.join(VUE, 'node_modules/@stylistic/eslint-plugin')]) {
  if (!fs.existsSync(needed)) {
    console.error(`missing ${path.relative(ROOT, needed)}: see tests/upstream/README.md`);
    process.exit(2);
  }
}
const TMP = fs.mkdtempSync(path.join(os.tmpdir(), 'veslint-vue-'));
process.on('exit', () => fs.rmSync(TMP, { recursive: true, force: true }));
const FIXTURES = path.join(TMP, 'fixtures');
try {
  execFileSync(path.join(ROOT, 'tests/upstream/vue/setup.sh'), [FIXTURES], { stdio: 'inherit' });
} catch {
  process.exit(2);
}
// eslint-plugin-vue makes its wrappers of ESLint Stylistic's rules when it loads, with the
// @stylistic/eslint-plugin it finds from the current directory (5.10.0, in the clone's node_modules
// that tools/gen_upstream_cases.mjs makes), and ESLint core's without it: it loads in the clone's root.
const CWD = fs.realpathSync(VUE);
process.chdir(CWD);
const require = createRequire(path.join(NM, 'x.js'));
const { RuleTester, ESLint, Linter } = require('eslint');
const { builtinRules } = require('eslint/use-at-your-own-risk');
const pluginVue = require('eslint-plugin-vue');
const PARSERS = {
  'vue-eslint-parser': require('vue-eslint-parser'),
  '@typescript-eslint/parser': require('@typescript-eslint/parser'),
  espree: require('espree'),
};
const { clearCaches } = PARSERS['@typescript-eslint/parser'];

let out = null;
const args = process.argv.slice(2);
if (args[0] === '--out') {
  out = path.resolve(args[1]);
  args.splice(0, 2);
}
const rules = args.length
  ? args
  : fs
      .readdirSync(path.join(ROOT, 'tests/rules/vue'))
      .filter(entry => fs.existsSync(path.join(ROOT, 'tests/rules/vue', entry, 'upstream.json')))
      .sort()
      .map(entry => `vue/${entry}`);

// `<cwd>/…` of a case: a path in the directory the case runs in.
const withCwd = value => {
  if (typeof value === 'string') return value === '<cwd>' || value.startsWith('<cwd>/') ? path.join(CWD, value.slice('<cwd>'.length)) : value;
  if (Array.isArray(value)) return value.map(withCwd);
  if (value && typeof value === 'object') return Object.fromEntries(Object.entries(value).map(([k, v]) => [k, withCwd(v)]));
  return value;
};

const parserOf = name => {
  if (name === null || name === undefined) return name;
  if (!PARSERS[name]) throw new Error(`unknown parser ${name}`);
  return PARSERS[name];
};
// parserOptions.parser of vue-eslint-parser: one parser or one per lang. Upstream gives the module
// or its path, which vue-eslint-parser requires: the same module.
const scriptParserOf = parser =>
  parser && typeof parser === 'object' ? Object.fromEntries(Object.entries(parser).map(([lang, name]) => [lang, parserOf(name)])) : parserOf(parser);

function languageOptionsOf(languageOptions = {}, parserName) {
  const result = { ...languageOptions };
  // espree is ESLint's default parser: a case that names it gave none.
  if (parserName && parserName !== 'espree') result.parser = parserOf(parserName);
  else if (result.parser !== undefined) result.parser = parserOf(result.parser);
  if (result.parserOptions && 'parser' in result.parserOptions) {
    result.parserOptions = { ...result.parserOptions, parser: scriptParserOf(result.parserOptions.parser) };
  }
  return result;
}

const pluginsOf = plugins =>
  plugins &&
  Object.fromEntries(
    Object.entries(plugins).map(([prefix, plugin]) => [
      prefix,
      plugin === 'eslint-plugin-vue' ? pluginVue : { rules: Object.fromEntries(plugin.rules.map(name => [name, pluginVue.rules[name]])) },
    ]),
  );

// The test case RuleTester receives.
function itemOf(c) {
  const item = { code: c.code };
  if (c.name !== undefined) item.name = c.name;
  if (c.options) item.options = withCwd(c.options);
  const parserOptions = { ...c.parserOptions };
  if (c.via === 'project') {
    item.filename = path.join(FIXTURES, c.file);
    parserOptions.project = [path.join(FIXTURES, c.tsconfig)];
  } else if (c.filename !== undefined) {
    item.filename = withCwd(c.filename);
  }
  const languageOptions = { ...c.languageOptions };
  if (Object.keys(parserOptions).length) languageOptions.parserOptions = parserOptions;
  item.languageOptions = languageOptionsOf(languageOptions, c.parser);
  if (c.settings) item.settings = withCwd(c.settings);
  if (c.plugins) item.plugins = pluginsOf(c.plugins);
  if (c.kind === 'invalid') {
    item.errors = c.errors;
    if ('output' in c) item.output = c.output;
  }
  return item;
}

// RuleTester runs each case in an `it` block: here it runs at once, and its failure is kept.
let failure = null;
RuleTester.describe = (title, fn) => fn();
RuleTester.it = (title, fn) => {
  try {
    fn();
  } catch (error) {
    failure = error;
  }
};
RuleTester.itOnly = RuleTester.it;

// The problems ESLint gives, the fields RuleTester and veslint look at.
const MESSAGE_KEYS = ['ruleId', 'severity', 'message', 'messageId', 'line', 'column', 'endLine', 'endColumn', 'fatal', 'fix', 'suggestions'];
const pick = m => Object.fromEntries(MESSAGE_KEYS.filter(k => k in m).map(k => [k, m[k]]));

function runCase(name, c) {
  const rule = c.rule ? builtinRules.get(c.rule) : pluginVue.rules[name];
  const tester = new RuleTester();
  // The problems of the first verify, the case's (the next ones check the output of the fixes).
  let messages = null;
  const verify = tester.linter.verify.bind(tester.linter);
  tester.linter.verify = (...verifyArgs) => {
    const result = verify(...verifyArgs);
    messages ??= result;
    return result;
  };
  failure = null;
  try {
    tester.run(c.rule ?? name, rule, c.kind === 'valid' ? { valid: [itemOf(c)], invalid: [] } : { valid: [], invalid: [itemOf(c)] });
  } catch (error) {
    failure = error;
  }
  return { failure, messages: (messages ?? []).map(pick) };
}

// A lint of an `it` block, linted again as the test did.
async function runLint(lint) {
  const { languageOptions, plugins, ...rest } = lint.config;
  const config = { ...rest };
  if (languageOptions) config.languageOptions = languageOptionsOf(languageOptions);
  if (plugins) config.plugins = pluginsOf(plugins);
  let messages;
  let output;
  if (lint.api === 'ESLint') {
    const eslint = new ESLint({ overrideConfigFile: true, overrideConfig: config, fix: Boolean(lint.fix) });
    const [result] = await eslint.lintText(lint.code, { filePath: lint.filename });
    messages = result.messages.map(pick);
    output = result.output;
  } else {
    messages = new Linter().verify(lint.code, config, lint.filename).map(pick);
  }
  const problems = [];
  if (JSON.stringify(messages) !== JSON.stringify(lint.messages)) {
    problems.push(`ESLint gives ${JSON.stringify(messages)}, recorded ${JSON.stringify(lint.messages)}`);
  }
  if (output !== lint.output) problems.push(`output ${JSON.stringify(output)}, recorded ${JSON.stringify(lint.output)}`);
  return problems;
}

// tests/upstream/vue/known.txt: `<case id>\t<why>` for the cases that do not give what their test
// expects with ESLint.
const KNOWN_FILE = path.join(ROOT, 'tests/upstream/vue/known.txt');
const known = new Map(
  (fs.existsSync(KNOWN_FILE) ? fs.readFileSync(KNOWN_FILE, 'utf8') : '')
    .split('\n')
    .filter(line => line.trim() && !line.startsWith('#'))
    .map(line => line.split('\t'))
    .map(([id, reason]) => [id, reason]),
);

// The test file of a case: its id without the case and the run (`<file>[/r<n>]/<v|i><n>`).
const testFileOf = id => id.split('/').slice(0, -1).filter((part, i, parts) => !(i === parts.length - 1 && /^r\d+$/.test(part))).join('/');

let failed = false;
let total = 0;
let different = 0;
let lastTestFile = null;
for (const ruleId of rules) {
  const name = ruleId.replace(/^vue\//, '');
  const data = JSON.parse(fs.readFileSync(path.join(ROOT, 'tests/rules/vue', name, 'upstream.json'), 'utf8'));
  const problems = [];
  const results = [];
  for (const c of data.cases) {
    const testFile = testFileOf(c.id);
    if (testFile !== lastTestFile) {
      clearCaches();
      lastTestFile = testFile;
    }
    const { failure: error, messages } = runCase(name, c);
    results.push({ filePath: c.id, messages });
    if (error && !known.has(c.id)) problems.push(`${c.id}: ${error.message.split('\n').slice(0, 6).join('\n    ')}`);
    if (!error && known.has(c.id)) problems.push(`${c.id}: listed in tests/upstream/vue/known.txt, but passes`);
    if (error) different++;
  }
  for (const lint of data.lints ?? []) {
    const lintProblems = await runLint(lint);
    if (lintProblems.length && !known.has(lint.id)) problems.push(...lintProblems.map(p => `${lint.id}: ${p}`));
    if (!lintProblems.length && known.has(lint.id)) problems.push(`${lint.id}: listed in tests/upstream/vue/known.txt, but passes`);
    if (lintProblems.length) different++;
  }
  const count = data.cases.length + (data.lints?.length ?? 0);
  total += count;
  if (out) {
    fs.mkdirSync(path.join(out, 'vue'), { recursive: true });
    fs.writeFileSync(path.join(out, 'vue', `${name}.json`), JSON.stringify(results));
  }
  if (problems.length) {
    failed = true;
    console.log(`FAIL   ${ruleId}: ${problems.length} unexpected difference(s) from the upstream test in ${count} cases`);
    for (const p of problems) console.log(`  ${p.replaceAll('\n', '\n    ')}`);
  } else {
    console.log(`ok     ${ruleId}: ${count} cases as the upstream test expects (known differences aside)`);
  }
}
console.log(`${total} cases, ${different} not as their test expects`);
process.exit(failed ? 1 : 0);
