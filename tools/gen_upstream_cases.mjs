// Extracts the test cases of the upstream tests of the rules veslint ports, so that the fixtures
// carry every case the rule has upstream: typescript-eslint's own tests and those of
// @slipher/eslint-plugin (the `seyfert/*` rules). Run with bun from the project root, after the
// sparse clones of typescript-eslint v8.62.0 in build/upstream/typescript-eslint and of
// tiramisulabs/extra at 221401c7c2 in build/upstream/extra, with seyfert 5.2.0 in
// build/upstream/seyfert (see tests/upstream/README.md):
//
//   bun tools/gen_upstream_cases.mjs [rule...]
//
// Each test file is loaded as the test runner would load it, but @typescript-eslint/rule-tester and
// vitest are replaced by the stubs in tools/upstream/: RuleTester.run records the cases. They are
// normalized as RuleTester does (default file name, merged parser options, dependency constraints)
// and written to tests/rules/<rule>/upstream.json, one case per line. The tests of
// @slipher/eslint-plugin that lint a project on disk (`lintProject` of its test/_disk.ts) run for
// real, with ESLint and the plugin's source, and the projects they lint go to the `projects` of
// upstream.json with the problems ESLint gives on them.
import fs from 'node:fs';
import path from 'node:path';
import { createRequire } from 'node:module';
import { pathToFileURL } from 'node:url';

const ROOT = path.resolve(import.meta.dir, '..');
const DEPENDENCIES = path.join(ROOT, 'build/eval/spider-byte/node_modules');

// Its real path: the test files name it through __dirname, which the runtime resolves (the clone
// may be reached through a symbolic link, as from an agent's copy of the project).
const realDir = dir => (fs.existsSync(dir) ? fs.realpathSync(dir) : dir);

const TYPESCRIPT_ESLINT = path.join(ROOT, 'build/upstream/typescript-eslint');
const EXTRA = path.join(ROOT, 'build/upstream/extra');
const SEYFERT_PACKAGE = path.join(EXTRA, 'packages/eslint-plugin');
const SEYFERT = path.join(ROOT, 'build/upstream/seyfert/node_modules/seyfert');
const ESLINT = path.join(ROOT, 'build/upstream/eslint');

// Where the tests of each plugin come from. `fixtures` is the directory the tests lint in, the one
// the files of the cases are written relative to.
const SOURCES = {
  '@typescript-eslint/': {
    label: 'typescript-eslint v8.62.0',
    clone: TYPESCRIPT_ESLINT,
    tests: path.join(TYPESCRIPT_ESLINT, 'packages/eslint-plugin/tests'),
    fixtures: realDir(path.join(TYPESCRIPT_ESLINT, 'packages/eslint-plugin/tests/fixtures')),
    modules: path.join(TYPESCRIPT_ESLINT, 'node_modules'),
    needs: [path.join(TYPESCRIPT_ESLINT, 'packages/eslint-plugin/tests')],
  },
  'seyfert/': {
    label: '@slipher/eslint-plugin 1.1.0 (tiramisulabs/extra 221401c7c2)',
    clone: EXTRA,
    tests: path.join(SEYFERT_PACKAGE, 'test'),
    fixtures: realDir(path.join(SEYFERT_PACKAGE, 'test')),
    modules: path.join(SEYFERT_PACKAGE, 'node_modules'),
    needs: [path.join(SEYFERT_PACKAGE, 'test'), SEYFERT],
    // The packages build/eval has in other versions: seyfert 5.2.0 instead, and not the preview of
    // the plugin Spider-Byte uses.
    leave: ['seyfert', '@slipher'],
    extra: { seyfert: SEYFERT },
  },
  // ESLint core (a rule id without a plugin): tests/lib/rules/<rule>.js of ESLint v10.6.0, written
  // for JavaScript. Each case is linted as TypeScript, in the file.ts (react.tsx with JSX) of
  // typescript-eslint's fixtures, without types.
  '': {
    label: 'eslint v10.6.0',
    core: true,
    clone: ESLINT,
    tests: path.join(ESLINT, 'tests/lib/rules'),
    fixtures: realDir(path.join(TYPESCRIPT_ESLINT, 'packages/eslint-plugin/tests/fixtures')),
    modules: path.join(ESLINT, 'node_modules'),
    needs: [path.join(ESLINT, 'tests/lib/rules'), path.join(ESLINT, 'lib/rules')],
  },
};

// A rule id with a plugin (`@typescript-eslint/…`, `seyfert/…`) or without one (ESLint core).
const sourceOf = rule =>
  rule.includes('/') ? Object.entries(SOURCES).find(([prefix]) => prefix && rule.startsWith(prefix)) : ['', SOURCES['']];

// <clone>/node_modules (for @slipher/eslint-plugin, its package's): the packages of build/eval
// (typescript-eslint 8.62.0, TypeScript 6.0.3), with the two stubs in place of the test framework.
function overlay(source) {
  const nm = source.modules;
  fs.rmSync(nm, { recursive: true, force: true });
  fs.mkdirSync(nm);
  const stub = (name, file) => {
    const dir = path.join(nm, name);
    fs.mkdirSync(dir, { recursive: true });
    fs.writeFileSync(path.join(dir, 'package.json'), JSON.stringify({ name, type: 'module', main: 'index.mjs' }));
    fs.symlinkSync(path.join(ROOT, 'tools/upstream', file), path.join(dir, 'index.mjs'));
  };
  for (const entry of fs.readdirSync(DEPENDENCIES)) {
    if (entry === '.bin' || entry === 'vitest' || source.leave?.includes(entry)) continue;
    const from = path.join(DEPENDENCIES, entry);
    if (entry.startsWith('@')) {
      fs.mkdirSync(path.join(nm, entry));
      for (const pkg of fs.readdirSync(from)) {
        if (entry === '@typescript-eslint' && pkg === 'rule-tester') continue;
        fs.symlinkSync(path.join(from, pkg), path.join(nm, entry, pkg));
      }
    } else {
      fs.symlinkSync(from, path.join(nm, entry));
    }
  }
  for (const [name, target] of Object.entries(source.extra ?? {})) fs.symlinkSync(realDir(target), path.join(nm, name));
  stub('@typescript-eslint/rule-tester', 'rule-tester.mjs');
  stub('vitest', 'vitest.mjs');
}

if (!fs.existsSync(DEPENDENCIES)) {
  console.error(`missing ${path.relative(ROOT, DEPENDENCIES)}: see tests/upstream/README.md`);
  process.exit(2);
}
const requireDependency = createRequire(path.join(DEPENDENCIES, 'x.js'));
const semver = requireDependency('semver');
const ts = requireDependency('typescript');
const versionOf = name => requireDependency(`${name}/package.json`).version;

// RuleTester's deepMerge: objects merge, everything else is replaced.
const isObject = value => typeof value === 'object' && value !== null && !Array.isArray(value);
function deepMerge(a = {}, b = {}) {
  const out = { ...a };
  for (const [key, value] of Object.entries(b)) {
    out[key] = isObject(value) && isObject(out[key]) ? deepMerge(out[key], value) : value;
  }
  return out;
}

function satisfies(constraints) {
  for (const [name, constraint] of Object.entries(constraints ?? {})) {
    const { range, options } = typeof constraint === 'string' ? { range: `>=${constraint}` } : constraint;
    const satisfiesOptions = isObject(options) ? { includePrerelease: true, ...options } : options;
    if (!semver.satisfies(versionOf(name), range, satisfiesOptions)) return false;
  }
  return true;
}

// The closest tsconfig.json going up from a file, as the project service finds it.
function closestTsconfig(file, fixtures) {
  for (let dir = path.dirname(file); dir.startsWith(fixtures); dir = path.dirname(dir)) {
    const candidate = path.join(dir, 'tsconfig.json');
    if (fs.existsSync(candidate)) return candidate;
  }
  return null;
}

// The files of a tsconfig, as TypeScript lists them from the disk.
const tsconfigFiles = new Map();
function filesOf(tsconfig) {
  if (!tsconfigFiles.has(tsconfig)) {
    const parsed = ts.getParsedCommandLineOfConfigFile(tsconfig, undefined, { ...ts.sys, onUnRecoverableConfigFileDiagnostic() {} });
    tsconfigFiles.set(tsconfig, new Set((parsed?.fileNames ?? []).map(file => path.resolve(file))));
  }
  return tsconfigFiles.get(tsconfig);
}

function assertPlain(value, where) {
  if (value instanceof RegExp || typeof value === 'function') throw new Error(`${where}: ${value} cannot be written as JSON`);
  if (Array.isArray(value)) value.forEach((v, i) => assertPlain(v, `${where}[${i}]`));
  else if (isObject(value)) for (const [k, v] of Object.entries(value)) assertPlain(v, `${where}.${k}`);
}

function normalize(run, raw, kind, index, prefix, source) {
  const fixtures = source.fixtures;
  const fixtureRelative = file => path.relative(fixtures, file).split(path.sep).join('/');
  const test = typeof raw === 'string' ? { code: raw } : raw;
  const id = `${prefix}/${kind[0]}${index}`;
  const { parser: caseParser, parserOptions: caseParserOptions, ...caseLanguageOptions } = test.languageOptions ?? {};
  // ESLint core: the RuleTester's own languageOptions (ecmaVersion, sourceType, globals) under the
  // case's, as flat config merges them.
  const { parser: _runParser, parserOptions: _runParserOptions, ...runLanguageOptions } = source.core
    ? (run.config.languageOptions ?? {})
    : {};
  const languageOptions = deepMerge(runLanguageOptions, caseLanguageOptions);
  const parserOptions = deepMerge(run.config.languageOptions?.parserOptions, caseParserOptions);
  const root = parserOptions.tsconfigRootDir ?? process.cwd();
  // The cases of ESLint core are JavaScript, linted as TypeScript: file.ts, or react.tsx with JSX
  // (the file name the test gives, a .js one, stays in `filename`).
  let filename = source.core
    ? parserOptions.ecmaFeatures?.jsx || /\.[jt]sx$/.test(test.filename ?? '')
      ? 'react.tsx'
      : 'file.ts'
    : (test.filename ?? (parserOptions.ecmaFeatures?.jsx ? 'react.tsx' : 'file.ts'));
  if (parserOptions.project) filename = path.join(root, filename);
  const file = path.isAbsolute(filename) ? filename : path.resolve(root, filename);
  // How the parser gets the types: the project service (the closest tsconfig.json), or the
  // program of `project`; neither: the case is only parsed. A file of the tests of
  // @slipher/eslint-plugin that the closest tsconfig.json does not have is one of the
  // `allowDefaultProject` files of the project service: a program of its own, with the options of
  // `defaultProject`.
  let tsconfig = null;
  let via = null;
  if (parserOptions.projectService) {
    tsconfig = closestTsconfig(file, fixtures);
    via = 'service';
    const service = parserOptions.projectService;
    if (source === SOURCES['seyfert/'] && isObject(service) && service.allowDefaultProject && !(tsconfig && filesOf(tsconfig).has(file))) {
      tsconfig = path.resolve(root, service.defaultProject ?? 'tsconfig.json');
      via = 'default';
    }
  } else if (typeof parserOptions.project === 'string') {
    tsconfig = path.resolve(root, parserOptions.project);
    via = 'project';
  } else if (parserOptions.project === true) {
    tsconfig = closestTsconfig(file, fixtures);
    via = 'project';
  } else if (parserOptions.project) {
    throw new Error(`${id}: project ${JSON.stringify(parserOptions.project)} is not handled`);
  }
  const {
    project: _project,
    projectService,
    tsconfigRootDir: _root,
    disallowAutomaticSingleRunInference: _single,
    ...otherParserOptions
  } = parserOptions;
  const out = { id, kind };
  if (test.name) out.name = test.name;
  out.code = test.code;
  if (test.options?.length) out.options = test.options;
  // Without a project the case is only parsed (no types), with the file name as given.
  out.file = tsconfig ? fixtureRelative(file) : filename;
  out.tsconfig = tsconfig && fixtureRelative(tsconfig);
  if (via) out.via = via;
  // tsconfigRootDir, when it is not the fixtures directory itself.
  if (tsconfig && path.resolve(root) !== fixtures) out.root = fixtureRelative(path.resolve(root));
  if (isObject(projectService)) out.projectService = projectService;
  if (Object.keys(otherParserOptions).length) out.parserOptions = otherParserOptions;
  if (Object.keys(languageOptions).length) out.languageOptions = languageOptions;
  if (source.core && test.filename) out.filename = test.filename;
  // A case of ESLint core with a parser of its own (one of its fixtures, often for TypeScript).
  if (source.core && caseParser) out.parser = caseParser.meta?.name ?? 'custom';
  if (test.settings) out.settings = test.settings;
  if (kind === 'invalid') {
    out.errors = test.errors;
    if ('output' in test) out.output = test.output;
  }
  if (test.before || test.after) out.hooks = true;
  if (test.only) out.only = true;
  if (test.skip) out.skip = 'skipped upstream';
  else if (!satisfies(test.dependencyConstraints)) out.skip = `dependencyConstraints ${JSON.stringify(test.dependencyConstraints)}`;
  assertPlain(out, id);
  return out;
}

const camelCase = name => name.replace(/-([a-z])/g, (_, letter) => letter.toUpperCase());

// The test files of a rule (its name without the prefix of its plugin).
function testFiles(name, source) {
  if (source.core) {
    const file = path.join(source.tests, `${name}.js`);
    return fs.existsSync(file) ? [file] : [];
  }
  if (source === SOURCES['seyfert/']) {
    const file = path.join(source.tests, `${camelCase(name)}.test.mts`);
    return fs.existsSync(file) ? [file] : [];
  }
  const file = path.join(source.tests, 'rules', `${name}.test.ts`);
  const dir = path.join(source.tests, 'rules', name);
  const files = [];
  if (fs.existsSync(file)) files.push(file);
  if (fs.existsSync(dir)) {
    for (const entry of fs.readdirSync(dir, { recursive: true }).sort()) {
      if (entry.endsWith('.test.ts')) files.push(path.join(dir, entry));
    }
  }
  return files;
}

// The rule itself, when its test file runs it under a label of its own; the tests of
// @slipher/eslint-plugin make the rule from its factory themselves, and run it under its name.
async function ruleObjectOf(name, source) {
  if (source === SOURCES['seyfert/']) return null;
  // The module the test file requires, the same object.
  if (source.core) return createRequire(path.join(source.clone, 'package.json'))(path.join(source.clone, 'lib/rules', `${name}.js`));
  return (await import(pathToFileURL(path.join(source.clone, 'packages/eslint-plugin/src/rules', `${name}.ts`)).href)).default;
}

// The tests of @slipher/eslint-plugin lint their projects on disk through `lintProject` of
// test/_disk.ts: it stays as it is, but it also gives the column of each problem, and it records
// each project it lints (its files, its rules, its tsconfig.json) with what ESLint gave.
const DISK_PATCHES = [
  ['export async function lintProject(', 'async function lintProjectUpstream('],
  ['line: message.line,', 'line: message.line,\n\t\t\t\tcolumn: message.column,'],
];
Bun.plugin({
  name: 'veslint-seyfert-disk',
  setup(build) {
    build.onLoad({ filter: /[\\/]eslint-plugin[\\/]test[\\/]_disk\.ts$/ }, async ({ path: file }) => {
      let text = await Bun.file(file).text();
      for (const [from, to] of DISK_PATCHES) {
        if (!text.includes(from)) throw new Error(`${file} changed: no \`${from}\` in it`);
        text = text.replace(from, to);
      }
      text += `
export async function lintProject(files: Record<string, string>, rules: Linter.RulesRecord): Promise<DiskResult[]> {
	const results = await lintProjectUpstream(files, rules);
	(globalThis as any).__veslintProjects?.push({ files, rules, tsconfig: JSON.parse(FIXTURE_TSCONFIG), results });
	return results;
}
`;
      return { contents: text, loader: 'ts' };
    });
  },
});

// ESLint's own RuleTester, while the tests of ESLint core load (they require it by its path): in
// require's cache under that path, so that `run` records the cases, as the stub of tools/upstream/
// does for typescript-eslint's.
class EslintRuleTester {
  constructor(config = {}) {
    this.config = config;
  }

  run(name, rule, tests) {
    (globalThis.__veslintRecorded ??= []).push({ name, rule, config: this.config, tests, messages: rule?.meta?.messages ?? {} });
  }

  static only(item) {
    return typeof item === 'string' ? { code: item, only: true } : { ...item, only: true };
  }

  static setDefaultConfig() {}

  static resetDefaultConfig() {}

  static getDefaultConfig() {
    return {};
  }
}
function stubEslintRuleTester() {
  const file = path.join(realDir(ESLINT), 'lib/rule-tester/rule-tester.js');
  const req = createRequire(path.join(realDir(ESLINT), 'package.json'));
  req.cache[file] = { id: file, filename: file, loaded: true, exports: EslintRuleTester, children: [], paths: [] };
  // tests/_utils requires fs-teardown, which is not installed, for createCustomTeardown; the rule
  // tests use only its unIndent, taken from its source.
  const utils = path.join(realDir(ESLINT), 'tests/_utils/index.js');
  const source = fs.readFileSync(utils, 'utf8');
  const unIndent = new Function(`${source.match(/^function unIndent[\s\S]*?^\}$/mu)[0]}\nreturn unIndent;`)();
  const createCustomTeardown = () => {
    throw new Error('createCustomTeardown is not stubbed');
  };
  req.cache[utils] = { id: utils, filename: utils, loaded: true, exports: { unIndent, createCustomTeardown }, children: [], paths: [] };
}

// A project recorded by `lintProject`: the file of each result as the test names it (the longest
// name the absolute path of the temporary project ends with), and its messages.
function normalizeProject(project, id, name) {
  const names = Object.keys(project.files);
  const results = project.results.map(result => {
    const file = names.filter(n => result.file.endsWith(`/${n}`)).sort((a, b) => b.length - a.length)[0];
    if (!file) throw new Error(`${id}: ${result.file} is none of the files of the project`);
    return { file, messages: result.messages };
  });
  const out = { id, name, files: project.files, rules: project.rules, tsconfig: project.tsconfig, results };
  assertPlain(out, id);
  return out;
}

const { recorded } = await import(pathToFileURL(path.join(ROOT, 'tools/upstream/rule-tester.mjs')).href);
// Some test files use vitest's globals without importing them.
const vitest = await import(pathToFileURL(path.join(ROOT, 'tools/upstream/vitest.mjs')).href);
for (const name of ['describe', 'suite', 'it', 'test', 'beforeAll', 'afterAll', 'beforeEach', 'afterEach', 'expect', 'vi']) {
  globalThis[name] = vitest[name];
}
// The rules by id: the path of their directory in tests/rules, the one with an expected.txt
// (`@typescript-eslint/await-thenable`, `seyfert/require-declare`); the files of the packages in a
// node_modules do not count.
const rules = process.argv.slice(2).length
  ? process.argv.slice(2)
  : fs
      .readdirSync(path.join(ROOT, 'tests/rules'), { recursive: true })
      .filter(file => path.basename(file) === 'expected.txt' && !file.split(path.sep).includes('node_modules'))
      .map(file => path.dirname(file).split(path.sep).join('/'));
const overlaid = new Set();
let failed = false;
for (const rule of rules.sort()) {
  const found = sourceOf(rule);
  if (!found) {
    console.error(`${rule}: no upstream tests for its plugin`);
    failed = true;
    continue;
  }
  const [prefix, source] = found;
  const missing = source.needs.filter(dir => !fs.existsSync(dir));
  if (missing.length) {
    console.error(`missing ${missing.map(dir => path.relative(ROOT, dir)).join(', ')}: see tests/upstream/README.md`);
    process.exit(2);
  }
  if (!overlaid.has(source)) {
    overlay(source);
    overlaid.add(source);
    if (source.core) stubEslintRuleTester();
  }
  const name = rule.slice(prefix.length);
  const files = testFiles(name, source);
  if (!files.length) {
    console.error(`${rule}: no test file upstream`);
    failed = true;
    continue;
  }
  const cases = [];
  const projects = [];
  let messages = {};
  const ruleObject = await ruleObjectOf(name, source);
  for (const file of files) {
    const before = recorded.length;
    const tests = source === SOURCES['seyfert/'] ? [] : undefined;
    globalThis.__veslintTests = tests;
    await import(pathToFileURL(file).href);
    // The tests of the projects on disk, with ESLint: each must pass, as upstream.
    globalThis.__veslintProjects = [];
    for (const test of tests ?? []) {
      const start = globalThis.__veslintProjects.length;
      try {
        await test.fn();
      } catch (error) {
        console.error(`${rule}: the upstream test "${test.name}" fails with ESLint: ${error.message}`);
        failed = true;
      }
      for (const project of globalThis.__veslintProjects.slice(start)) {
        projects.push(normalizeProject(project, `${name}/p${projects.length}`, test.name));
      }
    }
    globalThis.__veslintTests = undefined;
    globalThis.__veslintProjects = undefined;
    const runs = recorded.slice(before);
    if (runs.length) messages = runs[0].messages;
    const stem =
      source === SOURCES['seyfert/'] || source.core
        ? name
        : path.relative(path.join(source.tests, 'rules'), file).replace(/\.test\.ts$/, '').split(path.sep).join('/');
    runs.forEach((run, r) => {
      // A test file may run its rule more than once under a longer label
      // ("non-nullable-type-assertion-style - noUncheckedIndexedAccess"), or under a label of its
      // own; another rule is left out.
      if (run.rule !== ruleObject && run.name !== name && !run.name.startsWith(`${name} `)) {
        console.error(`${rule}: ${stem} runs ${run.name}; left out`);
        return;
      }
      const casePrefix = runs.length > 1 ? `${stem}/r${r}` : stem;
      (run.tests.valid ?? []).forEach((test, i) => cases.push(normalize(run, test, 'valid', i, casePrefix, source)));
      (run.tests.invalid ?? []).forEach((test, i) => cases.push(normalize(run, test, 'invalid', i, casePrefix, source)));
    });
  }
  const sourceFiles = files.map(f => path.relative(source.clone, f).split(path.sep).join('/'));
  const lines = cases.map(c => JSON.stringify(c));
  // meta.messages, to build the message of an expected error from its data, as RuleTester does.
  let text = `{"rule": ${JSON.stringify(rule)}, "upstream": "${source.label}", "files": ${JSON.stringify(sourceFiles)},\n"messages": ${JSON.stringify(messages)},\n"cases": [\n${lines.join(',\n')}\n]`;
  if (projects.length) text += `,\n"projects": [\n${projects.map(p => JSON.stringify(p)).join(',\n')}\n]`;
  text += '}\n';
  fs.writeFileSync(path.join(ROOT, 'tests/rules', rule, 'upstream.json'), text);
  const count = kind => cases.filter(c => c.kind === kind).length;
  const skipped = cases.filter(c => c.skip).length;
  console.log(
    `${rule}: ${count('valid')} valid, ${count('invalid')} invalid${skipped ? `, ${skipped} skipped` : ''}${projects.length ? `, ${projects.length} projects` : ''}`,
  );
}
process.exit(failed ? 1 : 0);
