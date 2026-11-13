// Reference config for tests/rules/reference.sh: typescript-eslint 8.62.0 (installed in build/eval
// by tests/eval_spider_byte.sh) and, for the `seyfert/*` rules, @slipher/eslint-plugin 1.1.0
// (build/upstream/seyfert, see tests/upstream/README.md). Each rule ported to veslint has a directory
// tests/rules/<rule id>/, and is enabled only on its cases.ts and cases.tsx files: with its default
// options or, in a subdirectory with options.json, with those.
import fs from 'node:fs';
import { createRequire } from 'node:module';
import path from 'node:path';
import tseslint from '../../build/eval/spider-byte/node_modules/typescript-eslint/dist/index.js';

const { plugin: seyfert } = createRequire(import.meta.url)(
  '../../build/upstream/seyfert/node_modules/@slipher/eslint-plugin',
);

// The directory of a rule is the one with an expected.txt, and its path is the rule's id
// (`@typescript-eslint/await-thenable`); the files of the packages in a node_modules do not count.
const ported = fs
  .readdirSync(import.meta.dirname, { recursive: true })
  .filter(file => path.basename(file) === 'expected.txt' && !file.split(path.sep).includes('node_modules'))
  .map(file => path.dirname(file))
  .sort();

const withDefaults = ported.map(rule => ({
  files: [`**/rules/${rule}/**/cases.ts`, `**/rules/${rule}/**/cases.tsx`],
  languageOptions: {
    parser: tseslint.parser,
    parserOptions: { projectService: true, tsconfigRootDir: import.meta.dirname },
  },
  plugins: { '@typescript-eslint': tseslint.plugin, seyfert },
  rules: { [rule]: 'error' },
}));

// A subdirectory with options.json (the list of options of the rule) tests other options.
const withOptions = ported.flatMap(rule =>
  fs
    .readdirSync(path.join(import.meta.dirname, rule), { recursive: true })
    .filter(file => path.basename(file) === 'options.json')
    .map(file => ({
      files: [`**/rules/${rule}/${path.dirname(file)}/cases.ts`, `**/rules/${rule}/${path.dirname(file)}/cases.tsx`],
      rules: {
        [rule]: [
          'error',
          ...JSON.parse(fs.readFileSync(path.join(import.meta.dirname, rule, file), 'utf8')),
        ],
      },
    })),
);

export default [...withDefaults, ...withOptions];
