// All the ported rules, with their default options, on every fixture of tests/rules: for
// tests/rules/cross.sh, which compares what ESLint and veslint report for a rule on the fixtures of
// the other rules. The `seyfert/*` rules are those of @slipher/eslint-plugin 1.1.0
// (build/upstream/seyfert).
import fs from 'node:fs';
import { createRequire } from 'node:module';
import path from 'node:path';
import tseslint from '../../build/eval/spider-byte/node_modules/typescript-eslint/dist/index.js';

const { plugin: seyfert } = createRequire(import.meta.url)(
  '../../build/upstream/seyfert/node_modules/@slipher/eslint-plugin',
);

const root = import.meta.dirname;
// The directory of a rule is the one with an expected.txt, and its path is the rule's id; the files
// of the packages in a node_modules do not count.
const ported = fs
  .readdirSync(root, { recursive: true })
  .filter(file => path.basename(file) === 'expected.txt' && !file.split(path.sep).includes('node_modules'))
  .map(file => path.dirname(file))
  .sort();
export default [
  {
    files: ['**/cases.ts', '**/cases.tsx'],
    languageOptions: {
      parser: tseslint.parser,
      parserOptions: { projectService: true, tsconfigRootDir: root },
    },
    plugins: { '@typescript-eslint': tseslint.plugin, seyfert },
    rules: Object.fromEntries(ported.map(rule => [rule, 'error'])),
  },
];
