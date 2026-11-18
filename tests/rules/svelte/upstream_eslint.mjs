// node tests/rules/svelte/upstream_eslint.mjs [--out DIR] [svelte/<rule>...]
//
// Runs the cases of tests/rules/svelte/<rule>/upstream.json (every rule without names) with ESLint
// 10.15.0 and the published eslint-plugin-svelte 3.24.1 of build/upstream/svelte-deps, through
// ESLint's own RuleTester, as the upstream tests run them (tests/utils/eslint-compat.ts hands them
// that class, tests/utils/utils.ts the cases of the fixtures): each case is given back its parser
// (svelte-eslint-parser, typescript-eslint's parser, espree), its parserOptions (the program of
// tests/fixtures/rules/tsconfig.json, the functions of its `_config.cjs`), languageOptions and
// settings, and RuleTester checks it as upstream does (the problems, their messages, lines,
// columns and suggestions, the output of one pass of fixes, no fatal error, no change to the AST).
// Each case runs alone: a failure is that case's. It shows that upstream.json holds the upstream
// tests faithfully. The cases the requirements of their fixture leave out (`skip`) do not run.
// The `lints` (the `it` blocks of comment-directive.ts) are linted again: ESLint must give the
// problems (and the output) recorded there.
//
// The cases run where upstream's run (eslint_run.mjs): in the package's directory, each one with
// its own file of tests/fixtures/rules.
//
// --out DIR writes DIR/svelte/<rule>.json, ESLint's problems for each case with its id as the file
// path, as tests/rules/upstream_eslint.mjs does. Exit code 1 when a case does not give what its
// test expects (unless tests/upstream/svelte/known.txt lists it), or a case listed there passes.
import fs from 'node:fs';
import path from 'node:path';
import { ROOT, runCase, lintMessages } from './eslint_run.mjs';

let out = null;
const args = process.argv.slice(2);
if (args[0] === '--out') {
  // eslint_run.mjs moved to the package's directory: a relative path is the caller's (PWD).
  out = path.resolve(process.env.PWD ?? '.', args[1]);
  args.splice(0, 2);
}
const DIR = path.join(ROOT, 'tests/rules/svelte');
// Every upstream.json under tests/rules/svelte (`@typescript-eslint/no-unnecessary-condition` is a
// level deeper).
const rules = args.length
  ? args
  : fs
      .readdirSync(DIR, { recursive: true })
      .filter(entry => path.basename(entry) === 'upstream.json')
      .map(entry => `svelte/${path.dirname(entry).split(path.sep).join('/')}`)
      .sort();

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

// tests/upstream/svelte/known.txt: `<case id>\t<why>` for the cases that do not give what their
// test expects with ESLint.
const KNOWN_FILE = path.join(ROOT, 'tests/upstream/svelte/known.txt');
const known = new Map(
  (fs.existsSync(KNOWN_FILE) ? fs.readFileSync(KNOWN_FILE, 'utf8') : '')
    .split('\n')
    .filter(line => line.trim() && !line.startsWith('#'))
    .map(line => line.split('\t'))
    .map(([id, reason]) => [id, reason]),
);

let failed = false;
let total = 0;
let skipped = 0;
let different = 0;
for (const ruleId of rules) {
  const name = ruleId.replace(/^svelte\//, '');
  const data = JSON.parse(fs.readFileSync(path.join(DIR, name, 'upstream.json'), 'utf8'));
  const problems = [];
  const results = [];
  let count = 0;
  for (const c of data.cases) {
    if (c.skip) {
      skipped++;
      continue;
    }
    count++;
    const { failure: error, messages } = runCase(name, c, data.languageOptions);
    results.push({ filePath: c.id, messages: messages ?? [] });
    if (error && !known.has(c.id)) problems.push(`${c.id} (${c.file}): ${error.message.split('\n').slice(0, 8).join('\n    ')}`);
    if (!error && known.has(c.id)) problems.push(`${c.id}: listed in tests/upstream/svelte/known.txt, but passes`);
    if (error) different++;
  }
  for (const lint of data.lints ?? []) {
    count++;
    const lintProblems = await runLint(lint);
    if (lintProblems.length && !known.has(lint.id)) problems.push(...lintProblems.map(p => `${lint.id}: ${p}`));
    if (!lintProblems.length && known.has(lint.id)) problems.push(`${lint.id}: listed in tests/upstream/svelte/known.txt, but passes`);
    if (lintProblems.length) different++;
  }
  total += count;
  if (out) {
    fs.mkdirSync(path.dirname(path.join(out, 'svelte', `${name}.json`)), { recursive: true });
    fs.writeFileSync(path.join(out, 'svelte', `${name}.json`), JSON.stringify(results));
  }
  if (problems.length) {
    failed = true;
    console.log(`FAIL   ${ruleId}: ${problems.length} unexpected difference(s) from the upstream test in ${count} cases`);
    for (const p of problems) console.log(`  ${p.replaceAll('\n', '\n    ')}`);
  } else {
    console.log(`ok     ${ruleId}: ${count} cases as the upstream test expects (known differences aside)`);
  }
}
console.log(`${total} cases (${skipped} skipped by their requirements, not run), ${different} not as their test expects`);
process.exit(failed ? 1 : 0);
