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
import path from 'node:path';
import { ROOT, runCase, lintMessages, clearCaches, testFileOf } from './eslint_run.mjs';

let out = null;
const args = process.argv.slice(2);
if (args[0] === '--out') {
  // eslint_run.mjs moved to the clone's root: a relative path is the caller's (PWD).
  out = path.resolve(process.env.PWD ?? '.', args[1]);
  args.splice(0, 2);
}
const rules = args.length
  ? args
  : fs
      .readdirSync(path.join(ROOT, 'tests/rules/vue'))
      .filter(entry => fs.existsSync(path.join(ROOT, 'tests/rules/vue', entry, 'upstream.json')))
      .sort()
      .map(entry => `vue/${entry}`);

// A lint of an `it` block, linted again as the test did.
async function runLint(lint) {
  const { messages, output } = await lintMessages(lint);
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
    results.push({ filePath: c.id, messages: messages ?? [] });
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
