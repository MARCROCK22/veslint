// How a case of tests/rules/svelte/<rule>/upstream.json runs in ESLint 10.15.0 with the published
// eslint-plugin-svelte 3.24.1 of build/upstream/svelte-deps, through ESLint's own RuleTester as
// the upstream tests run them (tests/utils/eslint-compat.ts hands them that class), and how a
// `lint` of an `it` block (comment-directive.ts) runs again.
//
// Importing it sets the process up as upstream's: the tests run in the package's directory,
// build/upstream/svelte/packages/eslint-plugin-svelte (mocha's), where the routes of SvelteKit of
// some svelte.config are, and from which the plugin loads typescript, sass, less and stylus (the
// node_modules there, links to build/upstream/svelte-deps, which tools/gen_upstream_cases.mjs makes);
// each case lints its own file of tests/fixtures/rules (`file`, `tsconfig` relative to it), in
// place: some rules and svelte-eslint-parser read the disk around it (svelte.config.js, sibling
// modules). All the test files run in one mocha process upstream: the program of
// tests/fixtures/rules/tsconfig.json is not rebuilt between them.
import fs from 'node:fs';
import path from 'node:path';
import { createRequire } from 'node:module';
import { pathToFileURL } from 'node:url';

export const ROOT = path.resolve(import.meta.dirname, '../../..');
const PACKAGE = path.join(ROOT, 'build/upstream/svelte/packages/eslint-plugin-svelte');
const NM = path.join(ROOT, 'build/upstream/svelte-deps/node_modules');
for (const needed of [NM, path.join(PACKAGE, 'tests/fixtures/rules'), path.join(PACKAGE, 'node_modules/typescript')]) {
  if (!fs.existsSync(needed)) {
    console.error(`missing ${path.relative(ROOT, needed)}: see tests/upstream/README.md`);
    process.exit(2);
  }
}
export const CWD = fs.realpathSync(PACKAGE);
export const FIXTURES = path.join(CWD, 'tests/fixtures/rules');
process.chdir(CWD);
export const require = createRequire(path.join(NM, 'x.js'));
const { RuleTester, ESLint } = require('eslint');
export const pluginSvelte = require('eslint-plugin-svelte');
export const PARSERS = {
  // The tests import it as a namespace (`import * as svelteParser`): the module itself.
  'svelte-eslint-parser': await import(pathToFileURL(require.resolve('svelte-eslint-parser')).href),
  '@typescript-eslint/parser': require('@typescript-eslint/parser'),
  espree: require('espree'),
};

const parserOf = name => {
  if (!PARSERS[name]) throw new Error(`unknown parser ${name}`);
  return PARSERS[name];
};

// The functions of a configuration from `_config.cjs` (`{"$function": source}` in upstream.json):
// the module's own, at the same place.
function withFunctions(value, original, where) {
  if (value && typeof value === 'object' && !Array.isArray(value) && '$function' in value) {
    if (typeof original !== 'function') throw new Error(`${where}: no function in the config module`);
    return original;
  }
  if (Array.isArray(value)) return value.map((v, i) => withFunctions(v, original?.[i], `${where}[${i}]`));
  if (value && typeof value === 'object') return Object.fromEntries(Object.entries(value).map(([k, v]) => [k, withFunctions(v, original?.[k], `${where}.${k}`)]));
  return value;
}

// The languageOptions of a case: those of its upstream.json (`defaults`: the browser globals of
// loadTestCases) under its own, the parser as a module (espree, ESLint's default, when the case
// names it: it gave none), parserOptions.parser by name (svelte-eslint-parser requires it), the
// program of `tsconfig`.
export function languageOptionsOf(c, defaults = {}) {
  const result = { ...defaults, ...c.languageOptions };
  if (c.parser && c.parser !== 'espree') result.parser = parserOf(c.parser);
  let parserOptions = { ...c.parserOptions };
  if (c.via === 'project') parserOptions.project = path.join(FIXTURES, c.tsconfig);
  else if (c.via) throw new Error(`${c.id}: via ${c.via} is not handled`);
  if (c.configModule) {
    const module = require(path.join(FIXTURES, c.configModule));
    parserOptions = withFunctions(parserOptions, module.languageOptions?.parserOptions, `${c.id}: parserOptions`);
  }
  if (Object.keys(parserOptions).length) result.parserOptions = parserOptions;
  return result;
}

// The test case RuleTester receives.
export function itemOf(c, defaults) {
  const item = { code: c.code, filename: path.join(FIXTURES, c.file) };
  if (c.name !== undefined) item.name = c.name;
  if (c.options) item.options = c.options;
  item.languageOptions = languageOptionsOf(c, defaults);
  if (c.settings) item.settings = c.settings;
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

// runCase runs a case of rule `name` (without `svelte/`) as RuleTester does: its failure (null when
// it gives what its test expects) and the problems of the first verify (the case's; the next ones
// check the output of the fixes), null when RuleTester failed before linting. `defaults` are the
// languageOptions of the case's upstream.json.
export function runCase(name, c, defaults) {
  const rule = pluginSvelte.rules[name];
  if (!rule) throw new Error(`no rule svelte/${name} in the published plugin`);
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
    const item = itemOf(c, defaults);
    tester.run(name, rule, c.kind === 'valid' ? { valid: [item], invalid: [] } : { valid: [], invalid: [item] });
  } catch (error) {
    failure = error;
  }
  // RuleTester names the rule it tests `rule-to-test/<name>`: the problems get its real id.
  const named = m => (m.ruleId?.startsWith('rule-to-test/') ? { ...m, ruleId: `svelte/${name}` } : m);
  return { failure, messages: messages && messages.map(m => pick(named(m))) };
}

const tsPlugin = () => createRequire(path.join(ROOT, 'build/eval/spider-byte/node_modules/x.js'))('@typescript-eslint/eslint-plugin');

// lintMessages runs a lint of an `it` block (ESLint with its configuration, the parser and the
// plugin by name): the problems and the output ESLint gives.
export async function lintMessages(lint) {
  if (lint.api !== 'ESLint') throw new Error(`${lint.id}: ${lint.api} is not handled`);
  const { languageOptions, plugins, ...rest } = lint.config;
  const config = { ...rest };
  if (languageOptions) {
    config.languageOptions = { ...languageOptions };
    if (languageOptions.parser) config.languageOptions.parser = parserOf(languageOptions.parser);
  }
  if (plugins) {
    config.plugins = Object.fromEntries(
      Object.entries(plugins).map(([prefix, plugin]) => {
        // typescript-eslint's plugin: the lints converted to TypeScript (upstream_ts.mjs) run its
        // no-unused-vars, from build/eval (8.72.2, as the parser).
        if (plugin === '@typescript-eslint/eslint-plugin') return [prefix, tsPlugin()];
        if (plugin !== 'eslint-plugin-svelte') throw new Error(`${lint.id}: unknown plugin ${plugin}`);
        return [prefix, pluginSvelte];
      }),
    );
  }
  const eslint = new ESLint({ overrideConfigFile: true, baseConfig: config });
  const [result] = await eslint.lintText(lint.code, { filePath: lint.filename });
  return { messages: result.messages.map(pick), output: result.output };
}
