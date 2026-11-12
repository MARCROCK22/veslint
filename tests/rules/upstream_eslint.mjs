// node tests/rules/upstream_eslint.mjs FIXTURES OUT rule-id...
//
// Runs ESLint 10.6.0 with typescript-eslint 8.62.0 (build/eval) on the cases of
// tests/rules/<rule>/upstream.json the way typescript-eslint's RuleTester runs its tests: the
// fixtures directory FIXTURES is one program, the case is the text of its file, parserOptions
// default to ecmaVersion "latest" and sourceType "module", and unused disable directives are
// reported. Writes OUT/<rule>.json, ESLint's JSON results with the id of each case as its file path.
// The `seyfert/*` rules are those of @slipher/eslint-plugin 1.1.0 (build/upstream/seyfert), whose
// tests lint in their own FIXTURES (tests/upstream/seyfert/setup.sh); the projects on disk of those
// tests (`projects` of upstream.json) are written again, as their test writes them, and ESLint
// must give the problems recorded there.
//
// It also checks each case against what the upstream test expects of it, as RuleTester would: no
// problem for a valid case; for an invalid one, the number of errors, their messageId, data, line,
// column, end, suggestions (with the text each one leaves) and the output of the fixes, pass after
// pass. A difference means the fixtures do not reproduce typescript-eslint's own test run; each one
// is printed and the exit code is 1.
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { createRequire } from 'node:module';

const ROOT = path.resolve(import.meta.dirname, '../..');
const NM = path.join(ROOT, 'build/eval/spider-byte/node_modules');
const require = createRequire(path.join(NM, 'x.js'));
const { ESLint, Linter } = require('eslint');
const SourceCodeFixer = require(path.join(NM, 'eslint/lib/linter/source-code-fixer.js'));
const { interpolate } = require(path.join(NM, 'eslint/lib/linter/interpolate.js'));
const tseslint = (await import(path.join(NM, 'typescript-eslint/dist/index.js'))).default;
const { clearCaches } = require('@typescript-eslint/parser');
const SEYFERT_PLUGIN = path.join(ROOT, 'build/upstream/seyfert/node_modules/@slipher/eslint-plugin');
const seyfert = fs.existsSync(SEYFERT_PLUGIN) ? require(SEYFERT_PLUGIN).plugin : null;

// The plugin of a rule and its name there.
function pluginOf(rule) {
  if (rule.startsWith('seyfert/')) {
    if (!seyfert) throw new Error(`missing ${SEYFERT_PLUGIN}: see tests/upstream/README.md`);
    return ['seyfert', seyfert, rule.slice('seyfert/'.length)];
  }
  return ['@typescript-eslint', tseslint.plugin, rule.replace('@typescript-eslint/', '')];
}

const [fixturesArg, outArg, ...ruleNames] = process.argv.slice(2);
const FIXTURES = path.resolve(fixturesArg);
const OUT = path.resolve(outArg);
fs.mkdirSync(OUT, { recursive: true });
// Upstream the tests run in packages/eslint-plugin, a directory above the fixtures: the program of
// `parserOptions.project` takes the current directory as its own, and `from: "file"` specifiers
// without a path match the files under it.
process.chdir(path.dirname(FIXTURES));

const linters = new Map();
function linterFor(cwd) {
  if (!linters.has(cwd)) linters.set(cwd, new Linter({ configType: 'flat', cwd }));
  return linters.get(cwd);
}

function configOf(rule, c, root) {
  const parserOptions = {
    ecmaVersion: 'latest',
    sourceType: 'module',
    ...c.parserOptions,
    disallowAutomaticSingleRunInference: true,
    tsconfigRootDir: root,
  };
  if (c.via === 'project') parserOptions.project = path.join(FIXTURES, c.tsconfig);
  else if (c.via === 'service' || c.via === 'default') parserOptions.projectService = c.projectService ?? true;
  const [prefix, plugin] = pluginOf(rule);
  return [
    {
      // A pattern that matches every file does not make ESLint lint one: name the extensions.
      files: ['**/*.ts', '**/*.tsx', '**/*.mts', '**/*.cts'],
      languageOptions: { ...c.languageOptions, parser: tseslint.parser, parserOptions },
      linterOptions: { reportUnusedDisableDirectives: 1 },
      plugins: { [prefix]: plugin },
      rules: { [rule]: ['error', ...(c.options ?? [])] },
      settings: c.settings ?? {},
    },
  ];
}

// The passes of fixes RuleTester makes: at most 10, each on the text the last one left.
function fixPasses(linter, code, config, file, messages) {
  const outputs = [];
  for (let pass = 0; pass < 10 && messages.length; pass++) {
    if (messages.some(m => m.fatal)) break;
    const fixed = SourceCodeFixer.applyFixes(code, messages);
    if (fixed.output === code) break;
    code = fixed.output;
    outputs.push(code);
    if (!fixed.fixed) break;
    messages = linter.verify(code, config, file);
  }
  return outputs;
}

const same = (a, b) => JSON.stringify(a) === JSON.stringify(b);

function check(rule, c, messages, outputs) {
  const problems = [];
  const say = text => problems.push(`${c.id}: ${text}`);
  if (c.kind === 'valid') {
    if (messages.length) say(`valid, but ${messages.length} problem(s): ${messages.map(m => m.messageId ?? m.message).join(', ')}`);
    return problems;
  }
  if (messages.some(m => m.fatal)) {
    say(`fatal: ${messages.find(m => m.fatal).message}`);
    return problems;
  }
  const [, plugin, name] = pluginOf(rule);
  const meta = plugin.rules[name].meta;
  const expected = typeof c.errors === 'number' ? null : c.errors;
  const count = typeof c.errors === 'number' ? c.errors : c.errors.length;
  if (messages.length !== count) say(`${messages.length} problem(s), expected ${count}`);
  if (expected) {
    expected.forEach((e, i) => {
      const m = messages[i];
      if (!m) return;
      if (typeof e === 'string') {
        if (m.message !== e) say(`error ${i}: message ${JSON.stringify(m.message)}, expected ${JSON.stringify(e)}`);
        return;
      }
      if ('messageId' in e && m.messageId !== e.messageId) say(`error ${i}: messageId ${m.messageId}, expected ${e.messageId}`);
      if ('message' in e && m.message !== e.message) say(`error ${i}: message ${JSON.stringify(m.message)}, expected ${JSON.stringify(e.message)}`);
      if ('data' in e && e.messageId && m.message !== interpolate(meta.messages[e.messageId], e.data)) {
        say(`error ${i}: message ${JSON.stringify(m.message)}, the data expect ${JSON.stringify(interpolate(meta.messages[e.messageId], e.data))}`);
      }
      for (const key of ['line', 'column', 'endLine', 'endColumn']) {
        if (key in e && m[key] !== e[key]) say(`error ${i}: ${key} ${m[key]}, expected ${e[key]}`);
      }
      if ('suggestions' in e) {
        const actual = m.suggestions ?? [];
        const wanted = e.suggestions ?? [];
        if (actual.length !== wanted.length) say(`error ${i}: ${actual.length} suggestion(s), expected ${wanted.length}`);
        wanted.forEach((s, j) => {
          const a = actual[j];
          if (!a) return;
          if ('messageId' in s && a.messageId !== s.messageId) say(`error ${i} suggestion ${j}: messageId ${a.messageId}, expected ${s.messageId}`);
          if ('desc' in s && a.desc !== s.desc) say(`error ${i} suggestion ${j}: desc ${JSON.stringify(a.desc)}, expected ${JSON.stringify(s.desc)}`);
          if ('output' in s) {
            const output = SourceCodeFixer.applyFixes(c.code, [a]).output;
            if (output !== s.output) say(`error ${i} suggestion ${j}: output differs:\n${output}\n--- expected\n${s.output}`);
          }
        });
      }
    });
  }
  if ('output' in c) {
    if (c.output == null) {
      if (outputs.length && outputs[0] !== c.code) say('fixed, but the test expects no fix');
    } else if (typeof c.output === 'string') {
      if (!same(outputs, [c.output])) say(`output differs: ${JSON.stringify(outputs)}\n--- expected\n${JSON.stringify([c.output])}`);
    } else if (!same(outputs, c.output)) {
      say(`outputs differ: ${JSON.stringify(outputs)}\n--- expected\n${JSON.stringify(c.output)}`);
    }
  }
  return problems;
}

// A project the upstream test lints on disk, written again as `lintProject` of
// @slipher/eslint-plugin's test/_disk.ts writes it (a temporary directory with its tsconfig.json,
// its files and seyfert linked into its node_modules) and linted the same way: ESLint must give the
// problems recorded in upstream.json for each file.
async function checkProject(project) {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'veslint-seyfert-'));
  try {
    fs.mkdirSync(path.join(root, 'node_modules'));
    fs.symlinkSync(fs.realpathSync(path.join(FIXTURES, 'node_modules/seyfert')), path.join(root, 'node_modules/seyfert'), 'dir');
    fs.writeFileSync(path.join(root, 'tsconfig.json'), JSON.stringify(project.tsconfig));
    for (const [name, code] of Object.entries(project.files)) {
      fs.mkdirSync(path.dirname(path.join(root, name)), { recursive: true });
      fs.writeFileSync(path.join(root, name), code);
    }
    const eslint = new ESLint({
      cwd: root,
      overrideConfigFile: true,
      overrideConfig: [
        {
          files: ['**/*.ts'],
          languageOptions: { parser: tseslint.parser, parserOptions: { project: ['./tsconfig.json'], tsconfigRootDir: root } },
          plugins: { seyfert },
          rules: project.rules,
        },
      ],
    });
    const results = await eslint.lintFiles(Object.keys(project.files).map(name => path.join(root, name)));
    const problems = [];
    for (const want of project.results) {
      const got = results.find(result => result.filePath === path.join(root, want.file));
      const messages = (got?.messages ?? []).map(m => ({ ruleId: m.ruleId, messageId: m.messageId, message: m.message, line: m.line, column: m.column }));
      if (!same(messages, want.messages)) problems.push(`${project.id}: ${want.file}: ESLint gives ${JSON.stringify(messages)}, recorded ${JSON.stringify(want.messages)}`);
    }
    return problems;
  } finally {
    fs.rmSync(root, { recursive: true, force: true });
  }
}

// The test file a case comes from: its id without the case and the run (`<file>[/r<n>]/<v|i><n>`).
const testFileOf = id => id.split('/').slice(0, -1).filter((part, i, parts) => !(i === parts.length - 1 && /^r\d+$/.test(part))).join('/');

// The cases tests/upstream/known.txt lists for ESLint, which must fail.
const known = new Map(
  fs
    .readFileSync(path.join(ROOT, 'tests/upstream/known.txt'), 'utf8')
    .split('\n')
    .filter(line => line.trim() && !line.startsWith('#'))
    .map(line => line.split('\t'))
    .filter(([tool]) => tool === 'eslint')
    .map(([, id, reason]) => [id, reason]),
);

let failed = false;
let lastTestFile = null;
for (const rule of ruleNames) {
  const data = JSON.parse(fs.readFileSync(path.join(ROOT, 'tests/rules', rule, 'upstream.json'), 'utf8'));
  const { cases } = data;
  const results = [];
  const problems = [];
  let run = 0;
  for (const c of cases) {
    if (c.skip) continue;
    run++;
    // Each test file runs in a process of its own, and RuleTester clears the parser's caches after
    // it: the program does not keep the texts the cases of another test file gave its files.
    const testFile = testFileOf(c.id);
    if (testFile !== lastTestFile) {
      clearCaches();
      lastTestFile = testFile;
    }
    const root = path.join(FIXTURES, c.root ?? '');
    const file = c.tsconfig ? path.join(FIXTURES, c.file) : path.join(root, c.file);
    const config = configOf(rule, c, root);
    const linter = linterFor(root);
    let messages;
    try {
      messages = linter.verify(c.code, config, file);
    } catch (error) {
      problems.push(`${c.id}: ESLint threw: ${error.message.split('\n')[0]}`);
      continue;
    }
    results.push({ filePath: c.id, messages });
    const outputs = c.kind === 'invalid' && 'output' in c ? fixPasses(linter, c.code, config, file, messages) : [];
    const caseProblems = check(rule, c, messages, outputs);
    if (caseProblems.length && !known.has(c.id)) problems.push(...caseProblems);
    if (!caseProblems.length && known.has(c.id)) problems.push(`${c.id}: listed in tests/upstream/known.txt, but passes`);
  }
  for (const project of data.projects ?? []) {
    run++;
    const projectProblems = await checkProject(project);
    if (projectProblems.length && !known.has(project.id)) problems.push(...projectProblems);
    if (!projectProblems.length && known.has(project.id)) problems.push(`${project.id}: listed in tests/upstream/known.txt, but passes`);
  }
  fs.mkdirSync(path.dirname(path.join(OUT, `${rule}.json`)), { recursive: true });
  fs.writeFileSync(path.join(OUT, `${rule}.json`), JSON.stringify(results));
  if (problems.length) {
    failed = true;
    console.log(`FAIL   ${rule}: ${problems.length} unexpected difference(s) from the upstream test in ${run} cases`);
    for (const p of problems) console.log(`  ${p.replaceAll('\n', '\n    ')}`);
  } else {
    console.log(`ok     ${rule}: ${run} cases as the upstream test expects (known differences aside)`);
  }
}
process.exit(failed ? 1 : 0);
