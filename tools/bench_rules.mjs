// Dev-time only: `node tools/bench_rules.mjs` writes tests/bench/syntactic-rules.json, the rules
// without type information of the benchmark (tests/bench/run.sh, set `syntactic`): the rules that
// @eslint/js's `recommended` and typescript-eslint's `recommended` turn on together (merged as a flat
// configuration does), kept when veslint, oxlint and Biome all have them. oxlint names them as ESLint
// does (`typescript/` for typescript-eslint's); it rejects a rule it does not have, which is how each
// is checked. Biome's rule (with its options) is what `biome migrate eslint` makes of the ESLint rule
// alone, the mapping Biome itself gives. Needs the ESLint of build/eval/spider-byte and the tools of
// build/bench (tests/bench/run.sh installs them).
import fs from 'node:fs';
import path from 'node:path';
import { createRequire } from 'node:module';
import { spawnSync } from 'node:child_process';

const root = path.join(import.meta.dirname, '..');
const eslintDir = path.join(root, 'build/eval/spider-byte/node_modules');
const bin = path.join(root, 'build/bench/node_modules/.bin');
const require = createRequire(path.join(eslintDir, 'typescript-eslint/package.json'));
const js = createRequire(path.join(eslintDir, 'eslint/package.json'))('@eslint/js');
const tseslint = require('typescript-eslint');

// The merged rules, as a flat configuration with both presets gives them to a .ts file.
const merged = { ...js.configs.recommended.rules };
for (const config of tseslint.configs.recommended) Object.assign(merged, config.rules ?? {});
const on = Object.entries(merged).filter(([, value]) => ![0, 'off'].includes(Array.isArray(value) ? value[0] : value)).map(([id]) => id).sort();

const veslintRules = new Set([...fs.readFileSync(path.join(root, 'rules/rules.v'), 'utf8').matchAll(/^pub const \w+ = '([^']+)'$/gm)].map(m => m[1]));
const tmp = fs.mkdtempSync(path.join(root, 'build/bench/rules-'));
fs.writeFileSync(path.join(tmp, 'a.ts'), 'export const a = 1;\n');

function oxlintName(id) {
  return id.startsWith('@typescript-eslint/') ? `typescript/${id.slice('@typescript-eslint/'.length)}` : id;
}

function oxlintHas(id) {
  fs.writeFileSync(path.join(tmp, 'oxlintrc.json'), JSON.stringify({ categories: { correctness: 'off' }, plugins: ['typescript'], rules: { [oxlintName(id)]: 'error' } }));
  const run = spawnSync(path.join(bin, 'oxlint'), ['-c', 'oxlintrc.json', 'a.ts'], { cwd: tmp, encoding: 'utf8' });
  return !/not found|Failed to parse/.test(run.stdout + run.stderr);
}

// Biome's rules for one ESLint rule: { "<group>/<rule>": level-or-{level, options} }.
function biomeOf(id) {
  const dir = fs.mkdtempSync(path.join(tmp, 'biome-'));
  fs.writeFileSync(path.join(dir, 'package.json'), '{}');
  fs.writeFileSync(path.join(dir, 'biome.json'), '{}');
  fs.writeFileSync(path.join(dir, 'eslint.config.mjs'), `export default [{ rules: ${JSON.stringify({ [id]: merged[id] })} }];\n`);
  spawnSync(path.join(bin, 'biome'), ['migrate', 'eslint', '--write'], { cwd: dir, encoding: 'utf8' });
  const rules = JSON.parse(fs.readFileSync(path.join(dir, 'biome.json'), 'utf8')).linter?.rules ?? {};
  const out = {};
  for (const [group, value] of Object.entries(rules)) {
    if (typeof value !== 'object' || value === null) continue;
    for (const [rule, setting] of Object.entries(value)) out[`${group}/${rule}`] = setting;
  }
  return out;
}

const kept = [];
const left = [];
for (const id of on) {
  const why = [];
  if (!veslintRules.has(id)) why.push('veslint');
  if (!oxlintHas(id)) why.push('oxlint');
  const biome = biomeOf(id);
  if (Object.keys(biome).length === 0) why.push('Biome');
  if (why.length > 0) left.push({ eslint: id, missingIn: why });
  else kept.push({ eslint: id, eslintSetting: merged[id], oxlint: oxlintName(id), biome });
}
fs.rmSync(tmp, { recursive: true, force: true });
const file = path.join(root, 'tests/bench/syntactic-rules.json');
fs.writeFileSync(file, JSON.stringify({ from: '@eslint/js recommended + typescript-eslint recommended', rules: kept, left }, null, 1) + '\n');
console.log(`${path.relative(root, file)}: ${kept.length} of ${on.length} rules (${left.length} left out)`);
