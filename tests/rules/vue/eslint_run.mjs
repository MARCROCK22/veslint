// Shared by tests/rules/vue/upstream_eslint.mjs and tests/rules/vue/upstream_ts.mjs: how a case of
// tests/rules/vue/<rule>/upstream.json (or of upstream.ts.json) runs in ESLint 10.15.0 with the
// published eslint-plugin-vue 10.12.1 of build/upstream/vue-deps, through ESLint's own RuleTester as
// the upstream tests run them (tests/eslint-compat.ts hands them that class), and how a `lint` of an
// `it` block runs again.
//
// Importing it sets the process up as upstream's: the cases run in the clone's root,
// build/upstream/vue (`<cwd>` in a case), with the clone's `dist` (the published build) and the
// node_modules tools/gen_upstream_cases.mjs makes there (tests/upstream/README.md); the typed ones
// lint src/test.vue of the directory tests/upstream/vue/setup.sh makes (a copy of the clone's
// tests/fixtures/typescript, with vue) in a temporary directory, removed on exit.
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { execFileSync } from 'node:child_process';
import { createRequire } from 'node:module';

export const ROOT = path.resolve(import.meta.dirname, '../../..');
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
export const FIXTURES = path.join(TMP, 'fixtures');
try {
  execFileSync(path.join(ROOT, 'tests/upstream/vue/setup.sh'), [FIXTURES], { stdio: 'inherit' });
} catch {
  process.exit(2);
}
// eslint-plugin-vue makes its wrappers of ESLint Stylistic's rules when it loads, with the
// @stylistic/eslint-plugin it finds from the current directory (5.10.0, in the clone's node_modules
// that tools/gen_upstream_cases.mjs makes), and ESLint core's without it: it loads in the clone's root.
export const CWD = fs.realpathSync(VUE);
process.chdir(CWD);
export const require = createRequire(path.join(NM, 'x.js'));
const { RuleTester, ESLint, Linter } = require('eslint');
const { builtinRules } = require('eslint/use-at-your-own-risk');
export const pluginVue = require('eslint-plugin-vue');
export const PARSERS = {
  'vue-eslint-parser': require('vue-eslint-parser'),
  '@typescript-eslint/parser': require('@typescript-eslint/parser'),
  espree: require('espree'),
};
export const { clearCaches } = PARSERS['@typescript-eslint/parser'];

// `<cwd>/…` of a case: a path in the directory the case runs in.
export const withCwd = value => {
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

export function languageOptionsOf(languageOptions = {}, parserName) {
  const result = { ...languageOptions };
  // espree is ESLint's default parser: a case that names it gave none.
  if (parserName && parserName !== 'espree') result.parser = parserOf(parserName);
  else if (result.parser !== undefined) result.parser = parserOf(result.parser);
  if (result.parserOptions && 'parser' in result.parserOptions) {
    result.parserOptions = { ...result.parserOptions, parser: scriptParserOf(result.parserOptions.parser) };
  }
  return result;
}

// The plugins of a configuration, by name: eslint-plugin-vue, typescript-eslint's (for the lints
// tests/rules/vue/upstream_ts.mjs converts), or a plugin with some rules of eslint-plugin-vue.
export const pluginsOf = plugins =>
  plugins &&
  Object.fromEntries(
    Object.entries(plugins).map(([prefix, plugin]) => [
      prefix,
      plugin === 'eslint-plugin-vue'
        ? pluginVue
        : plugin === '@typescript-eslint/eslint-plugin'
          ? require(path.join(ROOT, 'build/eval/spider-byte/node_modules/typescript-eslint/dist/index.js')).plugin
          : { rules: Object.fromEntries(plugin.rules.map(name => [name, pluginVue.rules[name]])) },
    ]),
  );

// The test case RuleTester receives.
export function itemOf(c) {
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
export const pick = m => Object.fromEntries(MESSAGE_KEYS.filter(k => k in m).map(k => [k, m[k]]));

// runCase runs a case of rule `name` (without `vue/`) as RuleTester does: its failure (null when it
// gives what its test expects) and the problems of the first verify (the case's; the next ones
// check the output of the fixes), null when RuleTester failed before linting.
export function runCase(name, c) {
  // A case of another rule: one of ESLint core, or of typescript-eslint (upstream_ts.mjs runs
  // jsx-uses-vars' cases of no-unused-vars with typescript-eslint's).
  const rule = c.rule
    ? c.rule.startsWith('@typescript-eslint/')
      ? pluginsOf({ ts: '@typescript-eslint/eslint-plugin' }).ts.rules[c.rule.slice('@typescript-eslint/'.length)]
      : builtinRules.get(c.rule)
    : pluginVue.rules[name];
  const tester = new RuleTester();
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
  // RuleTester names the rule it tests `rule-to-test/<name>`: the problems get its real id.
  const id = c.rule ?? `vue/${name}`;
  const named = m => (m.ruleId?.startsWith('rule-to-test/') ? { ...m, ruleId: id } : m);
  return { failure, messages: messages && messages.map(m => pick(named(m))) };
}

// lintMessages runs a lint of an `it` block (`api` ESLint or Linter, its configuration with the
// parsers and plugins by name): the problems and the output ESLint gives.
export async function lintMessages(lint) {
  const { languageOptions, plugins, ...rest } = lint.config;
  const config = { ...rest };
  if (languageOptions) config.languageOptions = languageOptionsOf(languageOptions);
  if (plugins) config.plugins = pluginsOf(plugins);
  if (lint.api === 'ESLint') {
    const eslint = new ESLint({ overrideConfigFile: true, overrideConfig: config, fix: Boolean(lint.fix) });
    const [result] = await eslint.lintText(lint.code, { filePath: lint.filename });
    return { messages: result.messages.map(pick), output: result.output };
  }
  return { messages: new Linter().verify(lint.code, config, lint.filename).map(pick), output: undefined };
}

// The test file of a case: its id without the case and the run (`<file>[/r<n>]/<v|i><n>`).
export const testFileOf = id => id.split('/').slice(0, -1).filter((part, i, parts) => !(i === parts.length - 1 && /^r\d+$/.test(part))).join('/');
