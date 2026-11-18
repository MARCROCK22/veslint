// Extracts the test cases of the upstream tests of the rules veslint ports, so that the fixtures
// carry every case the rule has upstream: typescript-eslint's own tests and those of
// @slipher/eslint-plugin (the `seyfert/*` rules). Run with bun from the project root, after the
// sparse clones of typescript-eslint v8.72.2 in build/upstream/typescript-eslint and of
// tiramisulabs/extra at 221401c7c2 in build/upstream/extra, with seyfert 5.2.0 in
// build/upstream/seyfert (see tests/upstream/README.md):
//
//   bun tools/gen_upstream_cases.mjs [rule...]
//
// A rule is named by its id (`@typescript-eslint/await-thenable`, `vue/html-indent`); `vue/` alone
// names every rule of eslint-plugin-vue, and `svelte/` every rule of eslint-plugin-svelte, whose
// cases are not tied to a ported rule yet.
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
const UNICORN = path.join(ROOT, 'build/upstream/unicorn');
const UNICORN_DEPS = path.join(ROOT, 'build/upstream/unicorn-deps/node_modules');
const STYLISTIC = path.join(ROOT, 'build/upstream/stylistic');
const PERFECTIONIST = path.join(ROOT, 'build/upstream/perfectionist');
const PERFECTIONIST_DEPS = path.join(ROOT, 'build/upstream/perfectionist-deps/node_modules');
const ESLINTCF = path.join(ROOT, 'build/upstream/eslintcf');
const VUE = path.join(ROOT, 'build/upstream/vue');
const VUE_DEPS = path.join(ROOT, 'build/upstream/vue-deps/node_modules');
const SVELTE = path.join(ROOT, 'build/upstream/svelte');
const SVELTE_PACKAGE = path.join(SVELTE, 'packages/eslint-plugin-svelte');
const SVELTE_DEPS = path.join(ROOT, 'build/upstream/svelte-deps/node_modules');

// Where the tests of each plugin come from. `fixtures` is the directory the tests lint in, the one
// the files of the cases are written relative to.
const SOURCES = {
  '@typescript-eslint/': {
    label: 'typescript-eslint v8.72.2',
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
  // ESLint core (a rule id without a plugin): tests/lib/rules/<rule>.js of ESLint v10.15.0, written
  // for JavaScript. Each case is linted as TypeScript, in the file.ts (react.tsx with JSX) of
  // typescript-eslint's fixtures, without types.
  '': {
    label: 'eslint v10.15.0',
    core: true,
    clone: ESLINT,
    tests: path.join(ESLINT, 'tests/lib/rules'),
    fixtures: realDir(path.join(TYPESCRIPT_ESLINT, 'packages/eslint-plugin/tests/fixtures')),
    modules: path.join(ESLINT, 'node_modules'),
    needs: [path.join(ESLINT, 'tests/lib/rules'), path.join(ESLINT, 'lib/rules')],
  },
  // eslint-plugin-unicorn v79.0.0 (the `unicorn/*` rules): test/<rule>.js, written for JavaScript
  // and linted, like ESLint core's, as TypeScript in the file.ts (react.tsx with JSX) of
  // typescript-eslint's fixtures. The cases of `test.snapshot` have no errors written: their
  // expectation is what ESLint gives with the configuration of the tests (espree and the globals of
  // test/utils/language-options.js), what made the snapshot.
  'unicorn/': {
    label: 'eslint-plugin-unicorn v79.0.0',
    unicorn: true,
    clone: UNICORN,
    tests: path.join(UNICORN, 'test'),
    fixtures: realDir(path.join(TYPESCRIPT_ESLINT, 'packages/eslint-plugin/tests/fixtures')),
    modules: path.join(UNICORN, 'node_modules'),
    needs: [path.join(UNICORN, 'test'), path.join(UNICORN_DEPS, 'outdent')],
    extra: { outdent: path.join(UNICORN_DEPS, 'outdent') },
  },
  // @stylistic/eslint-plugin v6.0.1 (the `@stylistic/*` rules): rules/<rule>/*.test.ts of
  // packages/eslint-plugin in eslint-stylistic, run by eslint-vitest-rule-tester 3.1.0 with
  // typescript-eslint's parser without types (`lang: 'ts'`, the default) or espree (`lang: 'js'`),
  // linted as TypeScript in the file.ts (react.tsx with JSX) of typescript-eslint's fixtures, one pass
  // of fixes, and an output checked only when the case gives one.
  '@stylistic/': {
    label: '@stylistic/eslint-plugin v6.0.1',
    stylistic: true,
    clone: STYLISTIC,
    tests: path.join(STYLISTIC, 'packages/eslint-plugin/rules'),
    fixtures: realDir(path.join(TYPESCRIPT_ESLINT, 'packages/eslint-plugin/tests/fixtures')),
    modules: path.join(STYLISTIC, 'node_modules'),
    needs: [path.join(STYLISTIC, 'packages/eslint-plugin/rules'), path.join(STYLISTIC, 'shared/test-utils')],
  },
  // eslint-plugin-perfectionist v5.13.0 (the `perfectionist/*` rules): test/rules/<rule>.test.ts
  // (and test/rules/<rule>/*.test.ts), whose `it` blocks call `valid` and `invalid` of
  // eslint-vitest-rule-tester 3.1.0's createRuleTester (tools/upstream/perfectionist-test.mjs):
  // espree without a parser, typescript-eslint's parser without types when the case names it, linted
  // as TypeScript in the file.ts (react.tsx with JSX) of typescript-eslint's fixtures; the fixes make
  // up to 11 passes and the output checked is the last one.
  'perfectionist/': {
    label: 'eslint-plugin-perfectionist v5.13.0',
    perfectionist: true,
    clone: PERFECTIONIST,
    tests: path.join(PERFECTIONIST, 'test/rules'),
    fixtures: realDir(path.join(TYPESCRIPT_ESLINT, 'packages/eslint-plugin/tests/fixtures')),
    modules: path.join(PERFECTIONIST, 'node_modules'),
    needs: [path.join(PERFECTIONIST, 'test/rules'), path.join(PERFECTIONIST_DEPS, 'dedent'), path.join(PERFECTIONIST_DEPS, 'natural-orderby')],
    extra: { dedent: path.join(PERFECTIONIST_DEPS, 'dedent'), 'natural-orderby': path.join(PERFECTIONIST_DEPS, 'natural-orderby') },
  },
  // @marcrock22/eslintcf 0.0.1 (the `marcrock/*` rules): src/rules/__test__/<rule>.test.ts (the
  // rule's name in camel case, some with `Rule` after it) of MARCROCK22/eslintcf at 0c25278, run by
  // bun's test runner with typescript-eslint's RuleTester (`bun:test` is the stub of vitest), linted
  // in the fixtures of typescript-eslint: without types (file.ts), or, with the project service and
  // `allowDefaultProject`, as default-project.ts in the default project, like unicorn's.
  'marcrock/': {
    label: '@marcrock22/eslintcf 0.0.1 (MARCROCK22/eslintcf 0c25278)',
    marcrock: true,
    clone: ESLINTCF,
    tests: path.join(ESLINTCF, 'src/rules/__test__'),
    fixtures: realDir(path.join(TYPESCRIPT_ESLINT, 'packages/eslint-plugin/tests/fixtures')),
    modules: path.join(ESLINTCF, 'node_modules'),
    needs: [path.join(ESLINTCF, 'src/rules/__test__')],
  },
  // eslint-plugin-vue v10.12.1 (the `vue/*` rules): tests/lib/rules/<rule>.test.ts (and
  // tests/lib/rules/<rule>/*.test.ts) of vuejs/eslint-plugin-vue, run by vitest with ESLint 10's
  // RuleTester through tests/eslint-compat.ts (tools/upstream/vue-test.mjs), with the packages of
  // build/upstream/vue-deps in place of the clone's devDependencies. The tests run in the clone's
  // root (file names without a directory are relative to it); the typed ones lint
  // src/test.vue of tests/fixtures/typescript with the program of its tsconfig.json. The cases
  // are Vue files, or JavaScript and TypeScript files parsed by vue-eslint-parser, espree or
  // typescript-eslint's parser: each one names its parsers and says what its script is.
  'vue/': {
    label: 'eslint-plugin-vue v10.12.1',
    vue: true,
    clone: VUE,
    tests: path.join(VUE, 'tests/lib/rules'),
    fixtures: realDir(path.join(VUE, 'tests/fixtures/typescript')),
    modules: path.join(VUE, 'node_modules'),
    dependencies: VUE_DEPS,
    needs: [path.join(VUE, 'tests/lib/rules'), path.join(VUE, 'lib/rules'), path.join(VUE, 'dist'), path.join(VUE_DEPS, 'eslint-plugin-vue/dist')],
  },
  // eslint-plugin-svelte v3.24.1 (the `svelte/*` rules): tests/src/rules/<rule>.ts of the package
  // packages/eslint-plugin-svelte of sveltejs/eslint-plugin-svelte, run by mocha with ESLint's
  // RuleTester (tests/utils/eslint-compat.ts: tools/upstream/svelte-test.mjs), with the packages of
  // build/upstream/svelte-deps in place of the monorepo's. Nearly every test file hands RuleTester
  // the cases loadTestCases of tests/utils/utils.ts reads from the fixtures of the rule
  // (tests/fixtures/rules/<rule>/{valid,invalid}/…): each one lints its own file there, with the
  // program of tests/fixtures/rules/tsconfig.json; the tests run in the package's directory.
  'svelte/': {
    label: 'eslint-plugin-svelte v3.24.1',
    svelte: true,
    clone: SVELTE_PACKAGE,
    tests: path.join(SVELTE_PACKAGE, 'tests/src/rules'),
    fixtures: realDir(path.join(SVELTE_PACKAGE, 'tests/fixtures/rules')),
    modules: path.join(SVELTE_PACKAGE, 'node_modules'),
    dependencies: SVELTE_DEPS,
    needs: [path.join(SVELTE_PACKAGE, 'tests/src/rules'), path.join(SVELTE_PACKAGE, 'src/rules'), path.join(SVELTE_DEPS, 'eslint-plugin-svelte/lib')],
  },
};

// A rule id with a plugin (`@typescript-eslint/…`, `seyfert/…`) or without one (ESLint core).
const sourceOf = rule =>
  rule.includes('/') ? Object.entries(SOURCES).find(([prefix]) => prefix && rule.startsWith(prefix)) : ['', SOURCES['']];

// <clone>/node_modules (for @slipher/eslint-plugin, its package's): the packages of build/eval
// (typescript-eslint 8.72.2, TypeScript 6.0.3), or those of the source's own `dependencies`
// (eslint-plugin-vue's), with the two stubs in place of the test framework.
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
  const dependencies = source.dependencies ?? DEPENDENCIES;
  for (const entry of fs.readdirSync(dependencies)) {
    if (entry === '.bin' || entry === 'vitest' || source.leave?.includes(entry)) continue;
    const from = path.join(dependencies, entry);
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
  // An extra package takes the place of the one of build/eval with its name (a link: removing it
  // leaves its target alone).
  for (const [name, target] of Object.entries(source.extra ?? {})) {
    fs.rmSync(path.join(nm, name), { force: true });
    fs.symlinkSync(realDir(target), path.join(nm, name));
  }
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
  const jsTests = source.core || source.unicorn || source.stylistic || source.perfectionist;
  const { parser: runParser, parserOptions: _runParserOptions, ...runLanguageOptions } = jsTests
    ? (run.config.languageOptions ?? {})
    : {};
  const languageOptions = deepMerge(runLanguageOptions, caseLanguageOptions);
  const parserOptions = deepMerge(run.config.languageOptions?.parserOptions, caseParserOptions);
  const root = parserOptions.tsconfigRootDir ?? process.cwd();
  // The cases of ESLint core are JavaScript, linted as TypeScript: file.ts, or react.tsx with JSX
  // (the file name the test gives, a .js one, stays in `filename`).
  let filename = jsTests
    ? parserOptions.ecmaFeatures?.jsx || /\.[jt]sx$/.test(test.filename ?? '')
      ? 'react.tsx'
      : 'file.ts'
    : (test.filename ?? (parserOptions.ecmaFeatures?.jsx ? 'react.tsx' : 'file.ts'));
  // A case of unicorn's tests (or of @marcrock22/eslintcf's) with `allowDefaultProject` lints a file
  // of no tsconfig.json, linted by the default project of the project service: the fixtures'
  // tsconfig.json has file.ts, so it is
  // default-project.ts here (a file of the fixtures that no tsconfig.json includes), linted with the
  // options of `defaultProject` (tsconfig.json of the fixtures) like a seyfert one (`via: default`).
  const unicornDefault = Boolean((source?.unicorn || source?.marcrock) && isObject(parserOptions.projectService)
    && parserOptions.projectService.allowDefaultProject && filename === 'file.ts');
  if (unicornDefault) filename = 'default-project.ts';
  if (parserOptions.project) filename = path.join(root, filename);
  const file = unicornDefault ? path.join(fixtures, filename) : path.isAbsolute(filename) ? filename : path.resolve(root, filename);
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
    if (unicornDefault) {
      tsconfig = path.join(fixtures, service.defaultProject ?? 'tsconfig.json');
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
  if (tsconfig && path.resolve(root) !== fixtures && !unicornDefault) out.root = fixtureRelative(path.resolve(root));
  if (isObject(projectService)) out.projectService = projectService;
  // An `allowDefaultProject` that names file.ts itself names the renamed file.
  if (unicornDefault && Array.isArray(projectService.allowDefaultProject)) {
    out.projectService = {
      ...projectService,
      allowDefaultProject: projectService.allowDefaultProject.map(glob => glob === 'file.ts' ? 'default-project.ts' : glob),
    };
  }
  if (Object.keys(otherParserOptions).length) out.parserOptions = otherParserOptions;
  if (Object.keys(languageOptions).length) out.languageOptions = languageOptions;
  if (jsTests && test.filename) out.filename = test.filename;
  // A case of ESLint core with a parser of its own (one of its fixtures, often for TypeScript), or
  // one of unicorn's with the parser of `test.typescript` or `test.vue`.
  if (source.core && caseParser) out.parser = caseParser.meta?.name ?? 'custom';
  if (source.unicorn && (caseParser ?? runParser)) out.parser = (caseParser ?? runParser).meta?.name ?? 'custom';
  // A case of @stylistic's tests with espree (`lang: 'js'`) or a parser of its own (Flow); of
  // perfectionist's without a parser (espree).
  if (source.stylistic || source.perfectionist) {
    const parser = caseParser ?? runParser;
    if (!parser) out.parser = 'espree';
    else if (parser.meta?.name !== 'typescript-eslint/parser') out.parser = parser.meta?.name ?? 'custom';
  }
  if (test.settings) out.settings = test.settings;
  if (kind === 'invalid' && run.mode === 'snapshot') {
    out.snapshot = true;
    Object.assign(out, unicornSnapshotExpectation(run, test, source));
  } else if (kind === 'invalid') {
    // eslint-vitest-rule-tester: an invalid case without errors expects at least one problem.
    if (test.errors !== undefined || !(source.stylistic || source.perfectionist)) out.errors = test.errors;
    if ('output' in test && test.output !== undefined) out.output = test.output;
  }
  if (test.before || test.after) out.hooks = true;
  if (test.only) out.only = true;
  if (test.skip) out.skip = 'skipped upstream';
  else if (out.parser === 'vue') out.skip = 'vue-eslint-parser: a Vue file, not TypeScript';
  else if (out.parser === 'html' || out.parser === 'svelte') out.skip = `the ${out.parser} parser: not TypeScript`;
  else if (out.parser === 'babel-flow') out.skip = 'Flow (@babel/eslint-parser): not TypeScript';
  else if (source.stylistic && !['ts', 'js'].includes(run.lang)) out.skip = `the ${run.lang} language: not TypeScript`;
  else if (source.stylistic && run.language) out.skip = `the ${run.language} language of the test's configs, not TypeScript`;
  else if (test.language) out.skip = `the ${test.language.name ?? test.language} language of ESLint, not TypeScript`;
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
  if (source.unicorn) {
    const file = path.join(source.tests, `${name}.js`);
    return fs.existsSync(file) ? [file] : [];
  }
  if (source === SOURCES['seyfert/']) {
    const file = path.join(source.tests, `${camelCase(name)}.test.mts`);
    return fs.existsSync(file) ? [file] : [];
  }
  if (source.marcrock) {
    const file = [`${camelCase(name)}.test.ts`, `${camelCase(name)}Rule.test.ts`].map(entry => path.join(source.tests, entry)).find(entry => fs.existsSync(entry));
    return file ? [file] : [];
  }
  if (source.perfectionist) {
    const file = path.join(source.tests, `${name}.test.ts`);
    const dir = path.join(source.tests, name);
    const files = fs.existsSync(file) ? [file] : [];
    if (fs.existsSync(dir)) {
      files.push(...fs.readdirSync(dir).filter(entry => entry.endsWith('.test.ts')).sort().map(entry => path.join(dir, entry)));
    }
    return files;
  }
  if (source.vue) {
    // no-unsupported-features has a test file per feature, in a directory of its own.
    const file = path.join(source.tests, `${name}.test.ts`);
    const dir = path.join(source.tests, name);
    const files = fs.existsSync(file) ? [file] : [];
    if (fs.existsSync(dir)) {
      files.push(...fs.readdirSync(dir).filter(entry => entry.endsWith('.test.ts')).sort().map(entry => path.join(dir, entry)));
    }
    return files;
  }
  if (source.svelte) {
    // One test file per rule (`@typescript-eslint/no-unnecessary-condition` in a directory).
    const file = path.join(source.tests, `${name}.ts`);
    return fs.existsSync(file) ? [file] : [];
  }
  if (source.stylistic) {
    // An experimental rule (`exp-jsx-props-style`) is tested in the directory of its source (`jsx-props-style`).
    const dir = path.join(source.tests, name.replace(/^exp-/, ''));
    return fs.existsSync(dir)
      ? fs.readdirSync(dir).filter(entry => entry.endsWith('.test.ts')).sort().map(entry => path.join(dir, entry))
      : [];
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
  if (source === SOURCES['seyfert/'] || source.marcrock) return null;
  // The source of the rule, which the test file imports: the same object.
  if (source.vue) return (await import(pathToFileURL(path.join(source.clone, 'lib/rules', `${name}.ts`)).href)).default;
  if (source.svelte) return (await import(pathToFileURL(path.join(source.clone, 'src/rules', `${name}.ts`)).href)).default;
  if (source.unicorn) return (await unicornPlugin()).rules[name];
  if (source.stylistic) return (await stylisticPlugin()).rules[name];
  if (source.perfectionist) return (await perfectionistPlugin()).rules[name];
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

// Bun's transpiler rewrites the raw text of a template literal (`String.raw\`👍\`` gives
// `\u{1f44d}`), so a test file of ESLint core loads from a copy next to it (its relative requires
// still resolve) where each String.raw template is the string it gives, computed from the raw
// parts espree reads.
const espree = requireDependency('espree');
function inlineStringRaw(text) {
  const ast = espree.parse(text, { ecmaVersion: 'latest', sourceType: 'script', range: true });
  const edits = [];
  const walk = node => {
    if (!node || typeof node.type !== 'string') return;
    const tag = node.type === 'TaggedTemplateExpression' ? node.tag : null;
    if (
      tag?.type === 'MemberExpression' &&
      !tag.computed &&
      tag.object.type === 'Identifier' &&
      tag.object.name === 'String' &&
      tag.property.name === 'raw'
    ) {
      const parts = [];
      node.quasi.quasis.forEach((quasi, i) => {
        parts.push(JSON.stringify(quasi.value.raw));
        const expression = node.quasi.expressions[i];
        if (expression) parts.push(`String(${text.slice(...expression.range)})`);
      });
      edits.push([node.range[0], node.range[1], `(${parts.join(' + ')})`]);
      return;
    }
    for (const [key, value] of Object.entries(node)) {
      if (key === 'parent') continue;
      if (Array.isArray(value)) value.forEach(walk);
      else if (value && typeof value.type === 'string') walk(value);
    }
  };
  walk(ast);
  for (const [start, end, replacement] of edits.sort((a, b) => b[0] - a[0])) {
    text = text.slice(0, start) + replacement + text.slice(end);
  }
  return text;
}
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

// eslint-plugin-unicorn's test/utils/test.js, the harness of its tests, is the stub of
// tools/upstream/unicorn-test.mjs while they load: it records their cases.
Bun.plugin({
  name: 'veslint-unicorn-tester',
  setup(build) {
    build.onLoad({ filter: /[\\/]unicorn[\\/]test[\\/]utils[\\/]test\.js$/ }, () => ({
      contents: `export * from ${JSON.stringify(path.join(ROOT, 'tools/upstream/unicorn-test.mjs'))};`,
      loader: 'js',
    }));
    // A test file of unicorn imports `node:test` for tests of its own outside RuleTester, which are
    // not cases of the rule: tools/upstream/node-test-stub.mjs takes its place (Bun cannot replace a
    // builtin module).
    build.onLoad({ filter: /[\\/]unicorn[\\/]test[\\/][^\\/]+\.js$/ }, ({ path: file }) => ({
      contents: fs.readFileSync(file, 'utf8').replaceAll(
        /from 'node:test'/g,
        `from ${JSON.stringify(path.join(ROOT, 'tools/upstream/node-test-stub.mjs'))}`,
      ),
      loader: 'js',
    }));
    // scripts/parsers.js, from which the test files of v79 import the parsers: the stub's.
    build.onLoad({ filter: /[\\/]unicorn[\\/]scripts[\\/]parsers\.js$/ }, () => ({
      contents: `export { typescriptEslintParser, vueEslintParser, htmlEslintParser, svelteEslintParser } from ${JSON.stringify(path.join(ROOT, 'tools/upstream/unicorn-test.mjs'))};`,
      loader: 'js',
    }));
    // test/utils/parsers.js: the parsers by name only (the stub's), as test.js gives them.
    build.onLoad({ filter: /[\\/]unicorn[\\/]test[\\/]utils[\\/]parsers\.js$/ }, () => ({
      contents: `import { parsers } from ${JSON.stringify(path.join(ROOT, 'tools/upstream/unicorn-test.mjs'))}; export default parsers;`,
      loader: 'js',
    }));
  },
});

// The test files of @stylistic/eslint-plugin import their harness as `#test` (shared/test-utils,
// an alias of its vitest configuration): the stub of tools/upstream/stylistic-test.mjs; and the
// source of their rule, which is not run: the rule of build/eval (@stylistic/eslint-plugin 5.10.0)
// gives its messages.
Bun.plugin({
  name: 'veslint-stylistic-tester',
  setup(build) {
    // Bun does not hand a `#` specifier to a plugin: the test file imports the stub by its path.
    build.onLoad({ filter: /[\\/]stylistic[\\/]packages[\\/]eslint-plugin[\\/]rules[\\/][^\\/]+[\\/][^\\/]+\.test\.ts$/ }, ({ path: file }) => {
      const text = fs.readFileSync(file, 'utf8').replaceAll(/from '#test(\/[^']*)?'/g, (_, sub) => {
        if (sub && sub !== '/parsers-flow' && sub !== '/parsers-jsx') throw new Error(`${file}: #test${sub} is not stubbed (tools/upstream/stylistic-test.mjs)`);
        return `from ${JSON.stringify(path.join(ROOT, 'tools/upstream/stylistic-test.mjs'))}`;
      });
      return { contents: text, loader: 'ts' };
    });
    build.onLoad({ filter: /[\\/]stylistic[\\/]packages[\\/]eslint-plugin[\\/]rules[\\/]([^\\/]+)[\\/][^\\/.]+\.ts$/ }, () => ({
      contents: 'export default {};',
      loader: 'js',
    }));
  },
});
// The test files of eslint-plugin-perfectionist import their tester (eslint-vitest-rule-tester), the
// tester of oxlint and a check of the schema from the stub of tools/upstream/perfectionist-test.mjs;
// the source of their rule is not run: the rule of build/upstream/perfectionist-deps (the same
// version) gives its messages. The helpers of the plugin (utils/alphabet.ts) are the real ones.
Bun.plugin({
  name: 'veslint-perfectionist-tester',
  setup(build) {
    const stub = JSON.stringify(path.join(ROOT, 'tools/upstream/perfectionist-test.mjs'));
    build.onLoad({ filter: /[\\/]perfectionist[\\/]test[\\/]rules[\\/].+\.test\.ts$/ }, ({ path: file }) => {
      const text = fs.readFileSync(file, 'utf8')
        .replaceAll(/from 'eslint-vitest-rule-tester'/g, `from ${stub}`)
        .replaceAll(/from '(?:\.\.?\/)+(?:rules\/)?build-oxlint-rule-tester'/g, `from ${stub}`)
        .replaceAll(/from '(?:\.\.?\/)+utils\/validate-rule-json-schema'/g, `from ${stub}`);
      return { contents: text, loader: 'ts' };
    });
    build.onLoad({ filter: /[\\/]perfectionist[\\/]rules[\\/][^\\/]+\.ts$/ }, () => ({ contents: 'export default {};', loader: 'js' }));
  },
});
// The test files of @marcrock22/eslintcf import their hooks from `bun:test`: the stub of vitest.
// The source of their rule (src/rules/<rule>.ts) is run: the test makes the rule from it.
Bun.plugin({
  name: 'veslint-marcrock-tester',
  setup(build) {
    build.onLoad({ filter: /[\\/]eslintcf[\\/]src[\\/]rules[\\/]__test__[\\/][^\\/]+\.test\.ts$/ }, ({ path: file }) => ({
      contents: fs.readFileSync(file, 'utf8').replaceAll(/from 'bun:test'/g, `from ${JSON.stringify(path.join(ROOT, 'tools/upstream/vitest.mjs'))}`),
      loader: 'ts',
    }));
  },
});
// The test files of eslint-plugin-vue import their harness from tests/eslint-compat.ts: the stub of
// tools/upstream/vue-test.mjs. Those that lint with ESLint import the plugin from the clone's
// `dist`, its build, which is the published one of build/upstream/vue-deps copied there
// (tests/upstream/README.md); a case of no-restricted-call-after-await also resolves the clone's
// package to it. The rule's source and the processor's (lib/) are the clone's, as upstream.
Bun.plugin({
  name: 'veslint-vue-tester',
  setup(build) {
    build.onLoad({ filter: /[\\/]vue[\\/]tests[\\/]eslint-compat\.ts$/ }, () => ({
      contents: `export * from ${JSON.stringify(path.join(ROOT, 'tools/upstream/vue-test.mjs'))};`,
      loader: 'js',
    }));
  },
});
// The packages of build/upstream/vue-deps, loaded when a rule of eslint-plugin-vue needs them (the
// other plugins' cases do not need them installed).
const requireVueDependency = name => createRequire(path.join(VUE_DEPS, 'x.js'))(name);
const vueEslintBuiltinRules = name => requireVueDependency('eslint/use-at-your-own-risk').builtinRules.get(name);
let vuePluginCache;
function vuePlugin() {
  vuePluginCache ??= requireVueDependency('eslint-plugin-vue');
  return vuePluginCache;
}

// The name of a parser as a case gives it: the module (vue-eslint-parser, typescript-eslint's
// parser, espree), its resolved path (`require.resolve('@typescript-eslint/parser')`) or the name of
// its package, which vue-eslint-parser requires; null stays null (the default parser).
const PARSER_NAMES = { 'vue-eslint-parser': 'vue-eslint-parser', 'typescript-eslint/parser': '@typescript-eslint/parser', espree: 'espree' };
function parserName(parser, where) {
  if (parser === null || parser === undefined) return parser;
  if (typeof parser === 'string') {
    if (!path.isAbsolute(parser)) return parser;
    const match = parser.split(path.sep).join('/').match(/.*\/node_modules\/((?:@[^/]+\/)?[^/]+)\//);
    if (!match) throw new Error(`${where}: the parser ${parser} is in no package`);
    return match[1];
  }
  const name = PARSER_NAMES[parser.meta?.name ?? parser.name];
  if (!name || (typeof parser.parse !== 'function' && typeof parser.parseForESLint !== 'function')) {
    throw new Error(`${where}: an unknown parser (${parser.meta?.name ?? parser.name})`);
  }
  return name;
}
// parserOptions.parser of vue-eslint-parser: one parser, or one per lang of the script (`{ts, js}`).
function scriptParserNames(parser, where) {
  if (isObject(parser) && typeof parser.parse !== 'function' && typeof parser.parseForESLint !== 'function') {
    return Object.fromEntries(Object.entries(parser).map(([lang, p]) => [lang, parserName(p, `${where}.${lang}`)]));
  }
  return parserName(parser, where);
}
function namedLanguageOptions(languageOptions, where) {
  if (!languageOptions) return {};
  const out = { ...languageOptions };
  if ('parser' in out) out.parser = parserName(out.parser, `${where}: languageOptions.parser`);
  if (out.parserOptions && 'parser' in out.parserOptions) {
    out.parserOptions = { ...out.parserOptions, parser: scriptParserNames(out.parserOptions.parser, `${where}: parserOptions.parser`) };
  }
  return out;
}

// A rule of the plugin as a test hands it (its source in lib/rules): its name, from its docs.
function vueRuleName(rule, where) {
  const name = rule?.meta?.docs?.url?.match(/\/rules\/([a-z-]+)\.html$/)?.[1];
  if (!name) throw new Error(`${where}: a rule that is none of eslint-plugin-vue's`);
  return name;
}
// The `plugins` of a configuration: eslint-plugin-vue itself, or a plugin of the test's own with
// some of its rules (`{vue: {rules: {'jsx-uses-vars': rule}}}`), written as their names.
function namedPlugins(plugins, where) {
  if (!plugins) return undefined;
  return Object.fromEntries(
    Object.entries(plugins).map(([prefix, plugin]) => {
      // The build in the clone's dist.
      if (plugin.meta?.name === 'eslint-plugin-vue' && plugin.rules && plugin.processors) return [prefix, 'eslint-plugin-vue'];
      const keys = Object.keys(plugin);
      if (keys.length !== 1 || keys[0] !== 'rules') throw new Error(`${where}: the plugin ${prefix} has ${keys.join(', ')}`);
      for (const [name, rule] of Object.entries(plugin.rules)) {
        if (vueRuleName(rule, `${where}: plugin ${prefix}`) !== name) throw new Error(`${where}: plugin ${prefix} names ${name} another rule`);
      }
      return [prefix, { rules: Object.keys(plugin.rules) }];
    }),
  );
}

// The tests run in the clone's root, and some give a path in it (a file name, or a module of an
// option: path.join(process.cwd(), …)): it is written as `<cwd>/…`, the directory the case runs in.
const VUE_ROOTS = [...new Set([realDir(VUE), VUE])];
function withCwd(value) {
  if (typeof value === 'string') {
    const root = VUE_ROOTS.find(r => value === r || value.startsWith(`${r}${path.sep}`));
    return root ? `<cwd>${value.slice(root.length).split(path.sep).join('/')}` : value;
  }
  if (Array.isArray(value)) return value.map(withCwd);
  if (isObject(value)) return Object.fromEntries(Object.entries(value).map(([k, v]) => [k, withCwd(v)]));
  return value;
}

// What the script of a case is, as vue-eslint-parser reads it. A Vue file (an SFC: vue-eslint-parser
// with a .vue file, or with a text that starts with `<`, its isVueFile) has the lang of the script
// it parses (`<script setup>` when there are two, else the first; `js` without a lang attribute),
// or `none` without a script; another file is TypeScript when its extension says so, or else when
// typescript-eslint's parser reads it (directly or as the parser of vue-eslint-parser), and
// JavaScript otherwise.
// The top-level elements come from vue-eslint-parser itself, without parsing the scripts
// (`parser: false`).
function scriptOf(code, filename, parser, parserOptions) {
  const sfc = parser === 'vue-eslint-parser' && (path.extname(filename ?? '<input>') === '.vue' || /^\s*</u.test(code));
  if (sfc) {
    const { services } = requireVueDependency('vue-eslint-parser').parseForESLint(code, { parser: false, filePath: 'file.vue', ecmaVersion: 'latest', sourceType: 'module' });
    const scripts = services.getDocumentFragment().children.filter(node => node.type === 'VElement' && node.name === 'script');
    const isSetup = element => element.startTag.attributes.some(a => !a.directive && a.key.name === 'setup');
    const langOf = element => element.startTag.attributes.find(a => !a.directive && a.key.name === 'lang')?.value?.value || 'js';
    const script = (scripts.length === 2 && scripts.find(isSetup)) || scripts[0];
    return { sfc, script: script ? langOf(script) : 'none', langs: [...new Set(scripts.map(langOf))] };
  }
  const extension = path.extname(filename ?? '').slice(1);
  if (/^[mc]?[jt]sx?$/.test(extension)) return { sfc, script: extension.replace(/^[mc]/, ''), langs: [] };
  const scriptParser = parser === 'vue-eslint-parser' ? parserOptions?.parser : parser;
  const ts = scriptParser === '@typescript-eslint/parser' || (isObject(scriptParser) && Object.values(scriptParser).includes('@typescript-eslint/parser'));
  return { sfc, script: ts ? 'ts' : 'js', langs: [] };
}

// The keys of a case that are not configuration (ESLint 10's RuleTesterParameters) and the keys of
// configuration these tests use; another one is not handled.
const RULE_TESTER_PARAMETERS = new Set(['name', 'code', 'filename', 'options', 'before', 'after', 'errors', 'output', 'only']);
const VUE_CONFIG_KEYS = new Set(['languageOptions', 'settings', 'plugins']);

// A case of eslint-plugin-vue's tests, as ESLint 10's RuleTester runs it: the configuration of the
// tester under the case's (flat config merges languageOptions, parserOptions and settings), the
// parsers by name, the file of the typed cases relative to tests/fixtures/typescript.
function normalizeVue(run, raw, kind, index, prefix, source, testedRule) {
  const test = typeof raw === 'string' ? { code: raw } : raw;
  const id = `${prefix}/${kind[0]}${index}`;
  for (const [where, object] of [['the tester', run.config], ['the case', test]]) {
    for (const key of Object.keys(object)) {
      if (!VUE_CONFIG_KEYS.has(key) && (where === 'the tester' || !RULE_TESTER_PARAMETERS.has(key))) {
        throw new Error(`${id}: ${where} has ${key}, which is not handled`);
      }
    }
  }
  const languageOptions = deepMerge(namedLanguageOptions(run.config.languageOptions, id), namedLanguageOptions(test.languageOptions, id));
  const { parser = 'espree', parserOptions: mergedParserOptions = {}, ...otherLanguageOptions } = languageOptions;
  const { project, ...parserOptions } = mergedParserOptions;
  const out = { id, kind };
  if (testedRule) out.rule = testedRule;
  if (test.name) out.name = test.name;
  out.code = test.code;
  if (test.options?.length) out.options = withCwd(test.options);
  // A typed case (tests/test-utils/typescript.ts): src/test.vue with the program of tsconfig.json.
  if (project) {
    const tsconfigs = (Array.isArray(project) ? project : [project]).map(p => path.resolve(p));
    if (tsconfigs.length !== 1 || !test.filename) throw new Error(`${id}: project ${JSON.stringify(project)} is not handled`);
    const relative = file => path.relative(source.fixtures, realDir(file)).split(path.sep).join('/');
    out.file = relative(path.resolve(test.filename));
    out.tsconfig = relative(tsconfigs[0]);
    if (out.file.startsWith('..') || out.tsconfig.startsWith('..')) throw new Error(`${id}: a typed case out of tests/fixtures/typescript`);
    out.via = 'project';
  } else if (test.filename !== undefined) {
    out.filename = withCwd(test.filename);
  }
  out.parser = parser;
  if (Object.keys(parserOptions).length) out.parserOptions = parserOptions;
  if (Object.keys(otherLanguageOptions).length) out.languageOptions = otherLanguageOptions;
  const settings = deepMerge(run.config.settings, test.settings);
  if (Object.keys(settings).length) out.settings = withCwd(settings);
  const plugins = namedPlugins(test.plugins ?? run.config.plugins, id);
  if (test.plugins && run.config.plugins) throw new Error(`${id}: plugins in the tester and in the case`);
  if (plugins) out.plugins = plugins;
  const { sfc, script, langs } = scriptOf(test.code, test.filename, parser, parserOptions);
  out.sfc = sfc;
  out.script = script;
  if (langs.length > 1) out.scripts = langs;
  if (kind === 'invalid') {
    out.errors = test.errors;
    if ('output' in test && test.output !== undefined) out.output = test.output;
  }
  if (test.before || test.after) out.hooks = true;
  if (test.only) out.only = true;
  assertPlain(out, id);
  return out;
}

// What an `it` block of the tests linted with ESLint or Linter (tools/upstream/vue-test.mjs): its
// configuration with the parsers, plugins and processor by name, the text, the file, and the
// problems ESLint gave (with the output of the fixes when the test fixes).
const MESSAGE_KEYS = ['ruleId', 'severity', 'message', 'messageId', 'line', 'column', 'endLine', 'endColumn', 'fatal', 'fix', 'suggestions'];
function normalizeVueLint(entry, id, name) {
  let config;
  let fix = false;
  if (entry.api === 'ESLint') {
    const { overrideConfigFile, overrideConfig, fix: fixOption, ...others } = entry.options;
    if (overrideConfigFile !== true || Object.keys(others).length) throw new Error(`${id}: ESLint options ${Object.keys(entry.options).join(', ')} are not handled`);
    config = overrideConfig;
    fix = Boolean(fixOption);
  } else {
    config = entry.config;
  }
  if (Array.isArray(config)) throw new Error(`${id}: a configuration array is not handled`);
  const { languageOptions, plugins, processor, ...rest } = config;
  const named = { ...rest };
  if (languageOptions) named.languageOptions = namedLanguageOptions(languageOptions, id);
  if (plugins) named.plugins = namedPlugins(plugins, id);
  if (processor) {
    // lib/processor.ts, the plugin's processor `vue`.
    if (typeof processor.preprocess !== 'function' || processor.meta?.name !== 'eslint-plugin-vue') throw new Error(`${id}: an unknown processor`);
    named.processor = 'vue/vue';
  }
  const pick = m => Object.fromEntries(MESSAGE_KEYS.filter(k => k in m).map(k => [k, m[k]]));
  const out = { id, name, api: entry.api, config: named };
  if (fix) out.fix = true;
  out.code = entry.code;
  out.filename = entry.filePath ?? entry.filename;
  if (entry.api === 'ESLint') {
    if (entry.results.length !== 1) throw new Error(`${id}: ${entry.results.length} results`);
    out.messages = entry.results[0].messages.map(pick);
    if (entry.results[0].output !== undefined) out.output = entry.results[0].output;
  } else {
    out.messages = entry.messages.map(pick);
  }
  assertPlain(out, id);
  return out;
}

// The test files of eslint-plugin-svelte import RuleTester from tests/utils/eslint-compat.ts: the
// stub of tools/upstream/svelte-test.mjs; comment-directive.ts takes loadESLint from `eslint`: the
// stub's too. tests/utils/utils.ts (loadTestCases) is the real one, with three changes: it lists a
// directory sorted, as node does (libuv sorts scandir; Bun does not), so that the cases come in
// upstream's order; a fixture its `_requirements.json` (or `<case>-requirements.json`) excludes
// with the packages installed is recorded (`__veslintSvelteSkipped`); and it never writes a
// missing errors.yaml or output (upstream writes them with ESLint the first time a fixture runs:
// here it is an error). tools/lib/write.ts, which it imports, would load prettier: a stub.
const SVELTE_UTILS_PATCHES = [
  ['for (const filename of fs.readdirSync(rootDir)) {', 'for (const filename of fs.readdirSync(rootDir).sort()) {'],
  [
    '\t\t) {\n\t\t\treturn false;\n\t\t}\n\t\treturn true;\n\t}',
    '\t\t) {\n\t\t\t(globalThis as any).__veslintSvelteSkipped?.push({ file: inputFile, requirements });\n\t\t\treturn false;\n\t\t}\n\t\treturn true;\n\t}',
  ],
  ['\tconst linter = new Linter();\n\tconst errorFile', '\tthrow new Error(`${inputFile}: its errors.yaml or output is missing (upstream writes it)`);\n\tconst linter = new Linter();\n\tconst errorFile'],
];
Bun.plugin({
  name: 'veslint-svelte-tester',
  setup(build) {
    const stub = JSON.stringify(path.join(ROOT, 'tools/upstream/svelte-test.mjs'));
    build.onLoad({ filter: /[\\/]eslint-plugin-svelte[\\/]tests[\\/]utils[\\/]eslint-compat\.ts$/ }, () => ({
      contents: `export { RuleTester } from ${stub};`,
      loader: 'js',
    }));
    build.onLoad({ filter: /[\\/]eslint-plugin-svelte[\\/]tools[\\/]lib[\\/]write\.ts$/ }, () => ({
      contents: `export async function writeAndFormat(file) { throw new Error(\`\${file}: the generator writes no fixture\`); }`,
      loader: 'js',
    }));
    build.onLoad({ filter: /[\\/]eslint-plugin-svelte[\\/]tests[\\/]utils[\\/]utils\.ts$/ }, ({ path: file }) => {
      let text = fs.readFileSync(file, 'utf8');
      for (const [from, to] of SVELTE_UTILS_PATCHES) {
        if (!text.includes(from)) throw new Error(`${file} changed: no \`${from}\` in it`);
        text = text.replace(from, to);
      }
      return { contents: text, loader: 'ts' };
    });
    build.onLoad({ filter: /[\\/]eslint-plugin-svelte[\\/]tests[\\/]src[\\/]rules[\\/]comment-directive\.ts$/ }, ({ path: file }) => {
      const text = fs.readFileSync(file, 'utf8');
      if (!text.includes("from 'eslint';")) throw new Error(`${file} changed: it does not import from 'eslint'`);
      return { contents: text.replace("from 'eslint';", `from ${stub};`), loader: 'ts' };
    });
  },
});
const requireSvelteDependency = name => createRequire(path.join(SVELTE_DEPS, 'x.js'))(name);
let sveltePluginCache;
function sveltePlugin() {
  sveltePluginCache ??= requireSvelteDependency('eslint-plugin-svelte');
  return sveltePluginCache;
}
let svelteParserCache;
async function svelteParser() {
  svelteParserCache ??= await import(pathToFileURL(createRequire(path.join(SVELTE_DEPS, 'x.js')).resolve('svelte-eslint-parser')).href);
  return svelteParserCache;
}

// The name of a parser of a case of eslint-plugin-svelte: the module (svelte-eslint-parser,
// typescript-eslint's parser, @babel/eslint-parser) or the name of its package (in
// parserOptions.parser, which svelte-eslint-parser requires from its own directory).
const SVELTE_PARSER_NAMES = { 'svelte-eslint-parser': 'svelte-eslint-parser', 'typescript-eslint/parser': '@typescript-eslint/parser', espree: 'espree' };
function svelteParserName(parser, where) {
  if (parser === null || parser === undefined || typeof parser === 'string') return parser;
  if (isObject(parser) && typeof parser.parse !== 'function' && typeof parser.parseForESLint !== 'function') {
    // parserOptions.parser of svelte-eslint-parser: one per lang of the script.
    return Object.fromEntries(Object.entries(parser).map(([lang, p]) => [lang, svelteParserName(p, `${where}.${lang}`)]));
  }
  const name = SVELTE_PARSER_NAMES[parser.meta?.name ?? parser.name];
  if (!name) throw new Error(`${where}: an unknown parser (${parser.meta?.name ?? parser.name})`);
  return name;
}

// A path of the package (the directory the tests run in) left in an option or a setting would not
// hold elsewhere: none is expected.
const SVELTE_ROOTS = [...new Set([realDir(SVELTE_PACKAGE), SVELTE_PACKAGE])];
function assertNoSveltePath(value, where) {
  if (typeof value === 'string' && SVELTE_ROOTS.some(root => value.includes(root))) throw new Error(`${where}: a path of the package (${value})`);
  if (Array.isArray(value)) value.forEach((v, i) => assertNoSveltePath(v, `${where}[${i}]`));
  else if (isObject(value)) for (const [k, v] of Object.entries(value)) assertNoSveltePath(v, `${where}.${k}`);
}

// A configuration of `_config.cjs` may hold functions (svelteConfig.onwarn, warningFilter,
// compilerOptions.runes): each is written `{"$function": <its source>}`, and the case names the
// module (`configModule`) the runner takes them from.
function withFunctions(value) {
  if (typeof value === 'function') return { $function: value.toString() };
  if (Array.isArray(value)) return value.map(withFunctions);
  if (isObject(value)) return Object.fromEntries(Object.entries(value).map(([k, v]) => [k, withFunctions(v)]));
  return value;
}
const hasFunction = value =>
  typeof value === 'function' || (Array.isArray(value) ? value.some(hasFunction) : isObject(value) && Object.values(value).some(hasFunction));

// The script of a case as svelte-eslint-parser reads it. A component (svelte-eslint-parser with a
// file that does not end in .svelte.js or .svelte.ts: a `.svelte`, or one of the other extensions
// of no-conflicting-module-names' fixtures) has the scripts of its top-level <script> elements in
// one program, whose lang is that of the attributes of all of them (each one's `lang` over the
// earlier one's, svelte-eslint-parser's context): parserOptions.parser[lang || 'js'] parses it,
// so `script` is that key (`ts`, `js`, or another lang as written), `none` without a script, and
// `scripts` the lang of each element when they differ. Another file (a .svelte.js/.svelte.ts
// module, which svelte-eslint-parser parses as a script, or a .js/.ts file) has the lang of its
// extension. `typescript` says whether typescript-eslint's parser reads the script.
async function svelteScriptOf(code, file, parser, parserOptions) {
  const svelte = parser === 'svelte-eslint-parser' && !/\.svelte\.[jt]s$/u.test(file);
  const scriptParserName = lang => {
    const p = parserOptions?.parser;
    if (typeof p === 'string') return p;
    if (isObject(p)) return p[lang || 'js'] ?? 'espree';
    return 'espree';
  };
  if (!svelte) {
    const lang = path.extname(file).slice(1).replace(/^[mc]/u, '');
    const reader = parser === 'svelte-eslint-parser' ? scriptParserName(lang) : parser;
    return { svelte, script: lang, langs: [], typescript: reader === '@typescript-eslint/parser' };
  }
  let elements;
  try {
    const { ast } = (await svelteParser()).parseForESLint(code, {
      ...parserOptions,
      filePath: 'file.svelte',
      ecmaVersion: 'latest',
      sourceType: 'module',
    });
    elements = ast.body
      .filter(node => node.type === 'SvelteScriptElement')
      .map(node =>
        Object.fromEntries(
          node.startTag.attributes
            .filter(a => a.type === 'SvelteAttribute' && Array.isArray(a.value) && a.value.length)
            .map(a => [a.key.name, a.value[0].type === 'SvelteLiteral' ? a.value[0].value : undefined]),
        ),
      );
  } catch {
    // A text svelte-eslint-parser rejects (a case of a parse error): its start tags, as written.
    elements = [...code.matchAll(/<script(\s[^>]*)?>/gu)].map(m =>
      Object.fromEntries([...(m[1] ?? '').matchAll(/([\w-]+)\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s"'>]+))/gu)].map(a => [a[1], a[2] ?? a[3] ?? a[4]])),
    );
  }
  if (!elements.length) return { svelte, script: 'none', langs: [], typescript: false };
  const merged = Object.assign({}, ...elements);
  const script = merged.lang || 'js';
  const langs = [...new Set(elements.map(attrs => attrs.lang || 'js'))];
  return { svelte, script, langs, typescript: scriptParserName(merged.lang) === '@typescript-eslint/parser' };
}

// The keys of a case of eslint-plugin-svelte's tests that are not configuration (ESLint 10's
// RuleTesterParameters) and the keys of configuration they use; another one is not handled.
const SVELTE_CONFIG_KEYS = new Set(['languageOptions', 'settings']);

// A case of eslint-plugin-svelte's tests, as ESLint 10's RuleTester runs it: the configuration of
// the tester under the case's (flat config merges languageOptions, parserOptions and settings),
// the parsers by name, the file relative to tests/fixtures/rules, the program of `project` (all
// the cases of loadTestCases: tests/fixtures/rules/tsconfig.json) as `tsconfig` and `via`.
async function normalizeSvelte(run, raw, kind, index, prefix, source) {
  const test = typeof raw === 'string' ? { code: raw } : raw;
  const id = `${prefix}/${kind[0]}${index}`;
  for (const [where, object] of [['the tester', run.config], ['the case', test]]) {
    for (const key of Object.keys(object)) {
      if (!SVELTE_CONFIG_KEYS.has(key) && (where === 'the tester' || !RULE_TESTER_PARAMETERS.has(key))) {
        throw new Error(`${id}: ${where} has ${key}, which is not handled`);
      }
    }
  }
  const named = languageOptions => {
    if (!languageOptions) return {};
    const out = { ...languageOptions };
    if ('parser' in out) out.parser = svelteParserName(out.parser, `${id}: languageOptions.parser`);
    if (out.parserOptions && 'parser' in out.parserOptions) {
      out.parserOptions = { ...out.parserOptions, parser: svelteParserName(out.parserOptions.parser, `${id}: parserOptions.parser`) };
    }
    return out;
  };
  const languageOptions = deepMerge(named(run.config.languageOptions), named(test.languageOptions));
  const { parser = 'espree', parserOptions: mergedParserOptions = {}, ...otherLanguageOptions } = languageOptions;
  const { project, ...parserOptions } = mergedParserOptions;
  const out = { id, kind };
  if (test.name) out.name = test.name;
  out.code = test.code;
  if (test.options?.length) out.options = test.options;
  if (!test.filename) throw new Error(`${id}: a case without a file`);
  const relative = file => path.relative(source.fixtures, realDir(path.dirname(file)) + path.sep + path.basename(file)).split(path.sep).join('/');
  out.file = relative(path.resolve(test.filename));
  if (out.file.startsWith('..')) throw new Error(`${id}: a file out of tests/fixtures/rules (${test.filename})`);
  if (project) {
    if (typeof project !== 'string') throw new Error(`${id}: project ${JSON.stringify(project)} is not handled`);
    out.tsconfig = relative(path.resolve(project));
    out.via = 'project';
  }
  out.parser = parser;
  if (Object.keys(parserOptions).length) out.parserOptions = withFunctions(parserOptions);
  if (Object.keys(otherLanguageOptions).length) out.languageOptions = otherLanguageOptions;
  // A configuration with functions: the `_config.cjs` it comes from (the closest one, as getConfig
  // finds it: `<case>-config.cjs` or `_config.cjs` of the directory).
  if (hasFunction(parserOptions) || hasFunction(otherLanguageOptions)) {
    const input = path.resolve(test.filename);
    const module = [
      input.replace(/(input|\+.+)(?:\.[a-z]+)+$/u, 'config.js'),
      path.join(path.dirname(input), '_config.js'),
      input.replace(/(input|\+.+)(?:\.[a-z]+)+$/u, 'config.cjs'),
      path.join(path.dirname(input), '_config.cjs'),
    ].find(f => fs.existsSync(f));
    if (!module) throw new Error(`${id}: functions in its configuration, from no config module`);
    out.configModule = relative(module);
  }
  const settings = deepMerge(run.config.settings, test.settings);
  if (Object.keys(settings).length) out.settings = settings;
  const { svelte, script, langs, typescript } = await svelteScriptOf(test.code, out.file, parser, parserOptions);
  out.svelte = svelte;
  out.script = script;
  if (langs.length > 1) out.scripts = langs;
  out.typescript = typescript;
  if (kind === 'invalid') {
    out.errors = test.errors;
    if ('output' in test && test.output !== undefined) out.output = test.output;
  }
  if (test.before || test.after) out.hooks = true;
  if (test.only) out.only = true;
  assertPlain(out, id);
  assertNoSveltePath({ options: out.options, settings: out.settings, parserOptions: out.parserOptions }, id);
  return out;
}

// A fixture loadTestCases leaves out because its requirements (`_requirements.json`) do not hold
// with the packages installed (ESLint 10, Svelte 5, TypeScript 6): its file and text, and why.
function normalizeSvelteSkipped(entry, index, prefix, source, ruleName) {
  const file = path.relative(source.fixtures, entry.file).split(path.sep).join('/');
  const kind = file.slice(ruleName.length + 1).split('/')[0];
  if (kind !== 'valid' && kind !== 'invalid') throw new Error(`${prefix}: ${file} is neither valid nor invalid`);
  const out = { id: `${prefix}/s${index}`, kind, name: path.join(ruleName, file.slice(ruleName.length + 1)), code: fs.readFileSync(entry.file, 'utf8'), file };
  out.skip = `requirements ${JSON.stringify(entry.requirements)}`;
  return out;
}

// What an `it` block of comment-directive.ts linted with ESLint (tools/upstream/svelte-test.mjs):
// its configuration with the parser, plugin and processor by name, the text, the file, and the
// problems ESLint gave.
function normalizeSvelteLint(entry, id, name) {
  if (entry.api !== 'ESLint') throw new Error(`${id}: ${entry.api} is not handled`);
  const { overrideConfigFile, baseConfig, ...others } = entry.options;
  if (overrideConfigFile !== true || Object.keys(others).length) throw new Error(`${id}: ESLint options ${Object.keys(entry.options).join(', ')} are not handled`);
  if (Array.isArray(baseConfig)) throw new Error(`${id}: a configuration array is not handled`);
  const { languageOptions, plugins, ...rest } = baseConfig;
  const named = { ...rest };
  if (languageOptions) {
    named.languageOptions = { ...languageOptions };
    if ('parser' in languageOptions) named.languageOptions.parser = svelteParserName(languageOptions.parser, `${id}: parser`);
  }
  if (plugins) {
    named.plugins = Object.fromEntries(
      Object.entries(plugins).map(([prefix, plugin]) => {
        if (plugin.meta?.name !== 'eslint-plugin-svelte') throw new Error(`${id}: the plugin ${prefix} is not eslint-plugin-svelte`);
        return [prefix, 'eslint-plugin-svelte'];
      }),
    );
  }
  if (typeof named.processor !== 'string' && named.processor !== undefined) throw new Error(`${id}: a processor object is not handled`);
  if (entry.results.length !== 1) throw new Error(`${id}: ${entry.results.length} results`);
  const pick = m => Object.fromEntries(MESSAGE_KEYS.filter(k => k in m).map(k => [k, m[k]]));
  const out = { id, name, api: entry.api, config: named, code: entry.code, filename: entry.filePath, messages: entry.results[0].messages.map(pick) };
  if (entry.results[0].output !== undefined) out.output = entry.results[0].output;
  assertPlain(out, id);
  return out;
}

let perfectionistPluginCache;
async function perfectionistPlugin() {
  perfectionistPluginCache ??= (await import(pathToFileURL(path.join(PERFECTIONIST_DEPS, 'eslint-plugin-perfectionist/dist/index.js')).href)).default;
  return perfectionistPluginCache;
}

let stylisticPluginCache;
async function stylisticPlugin() {
  stylisticPluginCache ??= (await import(pathToFileURL(requireDependency.resolve('@stylistic/eslint-plugin')).href)).default;
  return stylisticPluginCache;
}

// The plugin of build/eval (eslint-plugin-unicorn 79.0.0), the one Spider-Byte's configuration uses.
let unicornPluginCache;
async function unicornPlugin() {
  unicornPluginCache ??= (await import(pathToFileURL(requireDependency.resolve('eslint-plugin-unicorn')).href)).default;
  return unicornPluginCache;
}

// What the snapshot of an invalid case of `test.snapshot` holds, as RuleTester expectations: ESLint
// 10.15.0 run as test/utils/snapshot-rule-tester.js runs it (espree, or typescript-eslint's parser
// for `test.typescript`, and the globals of test/utils/language-options.js): each problem with its
// message, its range and its suggestions (with the text each one leaves), and the output of one
// pass of fixes (null when nothing is fixed).
const { Linter } = requireDependency('eslint');
const SourceCodeFixer = requireDependency(path.join(DEPENDENCIES, 'eslint/lib/linter/source-code-fixer.js'));
const globals = requireDependency('globals');
const UNICORN_GLOBALS = { ...globals.builtin, ...globals.node, ...globals.browser };
const JS_FILES = ['js', 'jsx', 'mjs', 'cjs', 'ts', 'tsx', 'mts', 'cts', 'vue'].map(extension => `**/*.${extension}`);
const snapshotLinter = new Linter({ configType: 'flat' });
function unicornSnapshotExpectation(run, test, source) {
  const name = run.name;
  const { parser: runParser, ...runLanguageOptions } = run.config.languageOptions ?? {};
  const { parser: caseParser, ...caseLanguageOptions } = test.languageOptions ?? {};
  const parserName = (caseParser ?? runParser)?.name;
  // A Vue file, or a case in another language of ESLint (CSS, JSON…): skipped, with no expectation.
  if (parserName === 'vue' || parserName === 'html' || parserName === 'svelte' || test.language) return { errors: [] };
  const languageOptions = deepMerge(deepMerge({ globals: UNICORN_GLOBALS }, runLanguageOptions), caseLanguageOptions);
  if (parserName === 'typescript') languageOptions.parser = requireDependency('@typescript-eslint/parser');
  // `parserOptions: {sourceType: 'script'}` of a case: its snapshot was taken with the code parsed as
  // a script (ESLint 10.15.0 passes languageOptions.sourceType, `module` by default, over it).
  if (!caseLanguageOptions.sourceType && caseLanguageOptions.parserOptions?.sourceType) {
    languageOptions.sourceType = caseLanguageOptions.parserOptions.sourceType;
  }
  const config = [
    {
      files: JS_FILES,
      languageOptions,
      plugins: { unicorn: unicornPluginCache },
      rules: { [`unicorn/${name}`]: ['error', ...(test.options ?? [])] },
      settings: { ...run.config.settings, ...test.settings },
      // As snapshot-rule-tester.js: no problem for an unused disable directive.
      linterOptions: { reportUnusedDisableDirectives: 'off' },
    },
  ];
  // Without a file name the snapshot tester lints `<input>`, which typescript-estree parses as TSX
  // when `ecmaFeatures.jsx` says so: react.tsx, as the case is linted.
  const tsx = parserName === 'typescript' && languageOptions.parserOptions?.ecmaFeatures?.jsx;
  const filename = test.filename ?? (tsx ? 'react.tsx' : parserName === 'typescript' ? 'file.ts' : 'file.js');
  const messages = snapshotLinter.verify(test.code, config, filename);
  const fatal = messages.find(m => m.fatal);
  if (fatal) throw new Error(`unicorn/${name}: a snapshot case does not parse: ${fatal.message}\n${test.code}`);
  const errors = messages.map(m => {
    const error = { messageId: m.messageId, message: m.message, line: m.line, column: m.column };
    if (m.endLine !== undefined) Object.assign(error, { endLine: m.endLine, endColumn: m.endColumn });
    error.suggestions = (m.suggestions ?? []).map(s => ({
      ...(s.messageId ? { messageId: s.messageId } : {}),
      desc: s.desc,
      output: SourceCodeFixer.applyFixes(test.code, [s]).output,
    }));
    return error;
  });
  const fixed = SourceCodeFixer.applyFixes(test.code, messages);
  return { errors, output: fixed.output === test.code ? null : fixed.output };
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
// `vue/` names every rule of eslint-plugin-vue (lib/rules/<rule>.ts of the clone).
const vueRules = () =>
  fs
    .readdirSync(path.join(VUE, 'lib/rules'))
    .filter(entry => entry.endsWith('.ts'))
    .map(entry => `vue/${entry.slice(0, -'.ts'.length)}`);
// `svelte/` names every rule of eslint-plugin-svelte (those of the published plugin, whose sources
// are src/rules/<rule>.ts of the clone).
const svelteRules = () => Object.keys(sveltePlugin().rules).map(name => `svelte/${name}`);
const rules = process.argv.slice(2).length
  ? process.argv.slice(2).flatMap(arg => (arg === 'vue/' ? vueRules() : arg === 'svelte/' ? svelteRules() : [arg]))
  : fs
      .readdirSync(path.join(ROOT, 'tests/rules'), { recursive: true })
      .filter(file => path.basename(file) === 'expected.txt' && !file.split(path.sep).includes('node_modules'))
      .map(file => path.dirname(file).split(path.sep).join('/'));
const overlaid = new Set();
let failed = false;
const START_CWD = process.cwd();
// The counts of the `vue/*` rules, in total.
const vueTotals = { rules: 0, cases: 0, valid: 0, invalid: 0, typed: 0, sfc: 0, sfcJs: 0, notSfc: 0, notSfcJs: 0, lints: 0 };
// The counts of the `svelte/*` rules, in total.
const svelteTotals = { rules: 0, cases: 0, valid: 0, invalid: 0, skipped: 0, typed: 0, svelte: 0, svelteTs: 0, svelteJs: 0, svelteOther: 0, svelteNone: 0, notSvelte: 0, notSvelteTs: 0, lints: 0 };
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
  // eslint-plugin-vue's tests run in the clone's root (vitest's root): their file names and the
  // paths they build with process.cwd() are relative to it.
  // eslint-plugin-svelte's run in its package's directory (mocha's): the routes of SvelteKit in
  // their svelte.config are relative to it, and the plugin loads typescript, sass, less… from it.
  process.chdir(source.vue ? realDir(VUE) : source.svelte ? realDir(SVELTE_PACKAGE) : START_CWD);
  if (source.svelte) globalThis.before ??= (await import(pathToFileURL(path.join(ROOT, 'tools/upstream/svelte-test.mjs')).href)).before;
  const name = rule.slice(prefix.length);
  const files = testFiles(name, source);
  if (!files.length) {
    console.error(`${rule}: no test file upstream`);
    failed = true;
    continue;
  }
  const cases = [];
  const projects = [];
  const lints = [];
  let messages = {};
  const ruleObject = await ruleObjectOf(name, source);
  for (const file of files) {
    const before = recorded.length;
    const tests = source === SOURCES['seyfert/'] || source.perfectionist || source.vue || source.svelte ? [] : undefined;
    globalThis.__veslintTests = tests;
    globalThis.__veslintSvelteSkipped = source.svelte ? [] : undefined;
    if (source.core) {
      const copy = file.replace(/\.js$/u, '.veslint-raw.js');
      fs.writeFileSync(copy, inlineStringRaw(fs.readFileSync(file, 'utf8')));
      try {
        await import(pathToFileURL(copy).href);
      } finally {
        fs.rmSync(copy);
      }
    } else {
      await import(pathToFileURL(file).href);
    }
    // The tests of the projects on disk, with ESLint: each must pass, as upstream. Those of
    // eslint-plugin-vue that lint with ESLint or Linter go to the `lints` of upstream.json.
    globalThis.__veslintProjects = [];
    globalThis.__veslintLints = [];
    for (const test of tests ?? []) {
      const start = globalThis.__veslintProjects.length;
      const lintStart = globalThis.__veslintLints.length;
      try {
        await test.fn();
      } catch (error) {
        // perfectionist's tests of the schema read the rule, which is not loaded: they make no case.
        if (source.perfectionist && /rule\.meta/.test(error.message)) continue;
        console.error(`${rule}: the upstream test "${test.name}" fails${source.perfectionist ? '' : ' with ESLint'}: ${error.message}`);
        failed = true;
      }
      for (const project of globalThis.__veslintProjects.slice(start)) {
        projects.push(normalizeProject(project, `${name}/p${projects.length}`, test.name));
      }
      for (const entry of globalThis.__veslintLints.slice(lintStart)) {
        lints.push(source.svelte ? normalizeSvelteLint(entry, `${name}/l${lints.length}`, test.name) : normalizeVueLint(entry, `${name}/l${lints.length}`, test.name));
      }
    }
    globalThis.__veslintTests = undefined;
    globalThis.__veslintProjects = undefined;
    globalThis.__veslintLints = undefined;
    const runs = recorded.slice(before);
    if (runs.length) messages = source.unicorn || source.stylistic || source.perfectionist ? (ruleObject.meta.messages ?? {}) : runs[0].messages;
    // eslint-plugin-vue: the messages of the published rule (the oracle), which must be those of
    // the source the tests run.
    // eslint-plugin-svelte: likewise, the published rule's.
    if (source.svelte) {
      messages = sveltePlugin().rules[name].meta.messages ?? {};
      if (JSON.stringify(messages) !== JSON.stringify(ruleObject.meta.messages ?? {})) {
        console.error(`${rule}: the messages of src/rules/${name}.ts are not those of the published rule`);
        failed = true;
      }
    }
    if (source.vue) {
      messages = vuePlugin().rules[name].meta.messages ?? {};
      if (JSON.stringify(messages) !== JSON.stringify(ruleObject.meta.messages ?? {})) {
        console.error(`${rule}: the messages of lib/rules/${name}.ts are not those of the published rule`);
        failed = true;
      }
    }
    // Every snapshot of unicorn's test file is one of the recorded invalid cases.
    if (source.unicorn) {
      // node's snapshots (test/snapshots/<rule>.js.snapshot, since v79): the first entry of each
      // invalid case, ` 1` (its code), is one case.
      const snapshotFile = path.join(source.tests, 'snapshots', `${name}.js.snapshot`);
      const snapshots = fs.existsSync(snapshotFile)
        ? (fs.readFileSync(snapshotFile, 'utf8').match(/^exports\[`[^\n]* > invalid\(\d+\): [^\n]* 1`\] = `$/gmu) ?? []).length
        : 0;
      const invalid = runs.filter(r => r.mode === 'snapshot').reduce((n, r) => n + (r.tests.invalid?.length ?? 0), 0);
      if (snapshots !== invalid) {
        console.error(`${rule}: ${invalid} invalid snapshot cases, ${snapshots} in ${path.relative(ROOT, snapshotFile)}`);
        failed = true;
      }
    }
    const stem =
      source === SOURCES['seyfert/'] || source.core || source.unicorn || source.marcrock || source.svelte
        ? name
        : source.vue
          ? path.relative(source.tests, file).replace(/\.test\.ts$/, '').split(path.sep).join('/')
        : source.stylistic
          ? path.basename(file).replace(/\.test\.ts$/, '')
          : source.perfectionist
            ? path.relative(source.tests, file).replace(/\.test\.ts$/, '').split(path.sep).join('/')
          : path.relative(path.join(source.tests, 'rules'), file).replace(/\.test\.ts$/, '').split(path.sep).join('/');
    // eslint-plugin-svelte: its rule under its own name, each case normalized (with
    // svelte-eslint-parser, asynchronously), then the fixtures its requirements leave out.
    if (source.svelte) {
      for (const [r, run] of runs.entries()) {
        if (run.rule !== ruleObject || run.name !== name) throw new Error(`${rule}: ${stem} runs ${run.name}, not the rule`);
        const casePrefix = runs.length > 1 ? `${stem}/r${r}` : stem;
        for (const [i, test] of (run.tests.valid ?? []).entries()) cases.push(await normalizeSvelte(run, test, 'valid', i, casePrefix, source));
        for (const [i, test] of (run.tests.invalid ?? []).entries()) cases.push(await normalizeSvelte(run, test, 'invalid', i, casePrefix, source));
      }
      globalThis.__veslintSvelteSkipped.forEach((entry, i) => cases.push(normalizeSvelteSkipped(entry, i, stem, source, name)));
      globalThis.__veslintSvelteSkipped = undefined;
      continue;
    }
    runs.forEach((run, r) => {
      // A test file may run its rule more than once under a longer label
      // ("non-nullable-type-assertion-style - noUncheckedIndexedAccess"), or under a label of its
      // own; another rule is left out.
      // An experimental rule of @stylistic runs under the name of its source (`list-style`).
      const runName = source.stylistic ? name.replace(/^exp-/, '') : name;
      const casePrefix = runs.length > 1 ? `${stem}/r${r}` : stem;
      // eslint-plugin-vue's tests run the rule under the name of their file
      // (`no-unsupported-features/v-memo`), and jsx-uses-vars' tests ESLint's no-unused-vars with
      // vue/jsx-uses-vars on: those cases name the rule they test.
      if (source.vue) {
        let testedRule;
        if (run.rule !== ruleObject) {
          if (run.rule !== vueEslintBuiltinRules(run.name)) throw new Error(`${rule}: ${stem} runs ${run.name}, a rule of its own`);
          testedRule = run.name;
          console.log(`${rule}: ${stem} runs ESLint's ${run.name}; its cases name it`);
        }
        (run.tests.valid ?? []).forEach((test, i) => cases.push(normalizeVue(run, test, 'valid', i, casePrefix, source, testedRule)));
        (run.tests.invalid ?? []).forEach((test, i) => cases.push(normalizeVue(run, test, 'invalid', i, casePrefix, source, testedRule)));
        return;
      }
      if (run.rule !== ruleObject && run.name !== runName && !run.name.startsWith(`${runName} `)) {
        console.error(`${rule}: ${stem} runs ${run.name}; left out`);
        return;
      }
      (run.tests.valid ?? []).forEach((test, i) => cases.push(normalize(run, test, 'valid', i, casePrefix, source)));
      (run.tests.invalid ?? []).forEach((test, i) => cases.push(normalize(run, test, 'invalid', i, casePrefix, source)));
    });
  }
  const sourceFiles = files.map(f => path.relative(source.clone, f).split(path.sep).join('/'));
  const lines = cases.map(c => JSON.stringify(c));
  // meta.messages, to build the message of an expected error from its data, as RuleTester does.
  let text = `{"rule": ${JSON.stringify(rule)}, "upstream": "${source.label}", "files": ${JSON.stringify(sourceFiles)},\n"messages": ${JSON.stringify(messages)},\n`;
  // The languageOptions every case has under its own: unicorn's tests give the globals of
  // test/utils/language-options.js.
  if (source.unicorn) text += `"languageOptions": ${JSON.stringify({ globals: UNICORN_GLOBALS })},\n`;
  // eslint-plugin-svelte: loadTestCases gives every case the browser globals of the `globals` its
  // tests import (16.4.0): when every case has them, they are written once here, the languageOptions
  // under each case's own (an upstream.json without them has no case of loadTestCases).
  if (source.svelte) {
    const browser = requireSvelteDependency('globals').browser;
    const run = cases.filter(c => !c.skip);
    const withBrowser = run.filter(c => c.languageOptions?.globals && JSON.stringify(c.languageOptions.globals) === JSON.stringify(browser));
    if (withBrowser.length && withBrowser.length !== run.length) throw new Error(`${rule}: ${withBrowser.length} of ${run.length} cases have the browser globals`);
    if (run.some(c => c.languageOptions?.globals && !withBrowser.includes(c))) throw new Error(`${rule}: globals other than the browser ones`);
    if (withBrowser.length) {
      for (const c of withBrowser) {
        delete c.languageOptions.globals;
        if (!Object.keys(c.languageOptions).length) delete c.languageOptions;
      }
      text += `"languageOptions": ${JSON.stringify({ globals: browser })},\n`;
    }
  }
  text += `"cases": [\n${(source.svelte ? cases.map(c => JSON.stringify(c)) : lines).join(',\n')}\n]`;
  if (projects.length) text += `,\n"projects": [\n${projects.map(p => JSON.stringify(p)).join(',\n')}\n]`;
  if (lints.length) text += `,\n"lints": [\n${lints.map(l => JSON.stringify(l)).join(',\n')}\n]`;
  text += '}\n';
  // The directory of a rule of eslint-plugin-vue may not exist yet: its cases come before its port.
  if (source.vue || source.svelte) fs.mkdirSync(path.join(ROOT, 'tests/rules', rule), { recursive: true });
  fs.writeFileSync(path.join(ROOT, 'tests/rules', rule, 'upstream.json'), text);
  const count = kind => cases.filter(c => c.kind === kind).length;
  const skipped = cases.filter(c => c.skip).length;
  if (source.svelte) {
    const run = cases.filter(c => !c.skip);
    const tally = {
      skipped: cases.length - run.length,
      typed: run.filter(c => c.via && c.typescript).length,
      svelte: run.filter(c => c.svelte).length,
      svelteTs: run.filter(c => c.svelte && c.typescript).length,
      svelteJs: run.filter(c => c.svelte && c.script === 'js').length,
      svelteOther: run.filter(c => c.svelte && !c.typescript && !['js', 'none'].includes(c.script)).length,
      svelteNone: run.filter(c => c.svelte && c.script === 'none').length,
      notSvelte: run.filter(c => !c.svelte).length,
      notSvelteTs: run.filter(c => !c.svelte && c.typescript).length,
    };
    console.log(
      `${rule}: ${run.filter(c => c.kind === 'valid').length} valid, ${run.filter(c => c.kind === 'invalid').length} invalid${tally.skipped ? ` (+${tally.skipped} skipped)` : ''}; ${tally.typed} typed; ${tally.svelte} components (${tally.svelteTs} TS, ${tally.svelteJs} JS, ${tally.svelteOther} other lang, ${tally.svelteNone} no script), ${tally.notSvelte} not components (${tally.notSvelteTs} TS)${lints.length ? `, ${lints.length} lints` : ''}`,
    );
    svelteTotals.rules++;
    svelteTotals.cases += run.length;
    svelteTotals.valid += run.filter(c => c.kind === 'valid').length;
    svelteTotals.invalid += run.filter(c => c.kind === 'invalid').length;
    svelteTotals.lints += lints.length;
    for (const key of Object.keys(tally)) svelteTotals[key] += tally[key];
    continue;
  }
  if (source.vue) {
    const tally = {
      typed: cases.filter(c => c.via).length,
      sfc: cases.filter(c => c.sfc).length,
      sfcJs: cases.filter(c => c.sfc && /^jsx?$/.test(c.script)).length,
      notSfc: cases.filter(c => !c.sfc).length,
      notSfcJs: cases.filter(c => !c.sfc && /^jsx?$/.test(c.script)).length,
    };
    console.log(
      `${rule}: ${count('valid')} valid, ${count('invalid')} invalid; ${tally.typed} typed, ${tally.sfc} .vue (${tally.sfcJs} with a JavaScript script), ${tally.notSfc} not .vue (${tally.notSfcJs} JavaScript)${lints.length ? `, ${lints.length} lints` : ''}`,
    );
    vueTotals.rules++;
    vueTotals.cases += cases.length;
    vueTotals.valid += count('valid');
    vueTotals.invalid += count('invalid');
    vueTotals.lints += lints.length;
    for (const key of Object.keys(tally)) vueTotals[key] += tally[key];
    continue;
  }
  console.log(
    `${rule}: ${count('valid')} valid, ${count('invalid')} invalid${skipped ? `, ${skipped} skipped` : ''}${projects.length ? `, ${projects.length} projects` : ''}`,
  );
}
if (svelteTotals.rules > 1) {
  const t = svelteTotals;
  console.log(
    `eslint-plugin-svelte: ${t.rules} rules, ${t.cases} cases (${t.valid} valid, ${t.invalid} invalid) + ${t.skipped} skipped by their requirements; ${t.typed} typed; ${t.svelte} components (${t.svelteTs} TS script, ${t.svelteJs} JS, ${t.svelteOther} other lang, ${t.svelteNone} no script), ${t.notSvelte} not components (${t.notSvelteTs} TS); ${t.lints} lints`,
  );
}
if (vueTotals.rules > 1) {
  const t = vueTotals;
  console.log(
    `eslint-plugin-vue: ${t.rules} rules, ${t.cases} cases (${t.valid} valid, ${t.invalid} invalid); ${t.typed} typed, ${t.sfc} .vue (${t.sfcJs} with a JavaScript script), ${t.notSfc} not .vue (${t.notSfcJs} JavaScript); ${t.lints} lints`,
  );
}
process.chdir(START_CWD);
process.exit(failed ? 1 : 0);
