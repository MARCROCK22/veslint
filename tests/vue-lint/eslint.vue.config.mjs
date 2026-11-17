// Every rule veslint has, with its default options, on .vue files as a Vue project lints them:
// vue-eslint-parser 10.4.2 with typescript-eslint's parser for the scripts and the types of the
// project service (extraFileExtensions ['.vue']), or of `parserOptions.project` with
// VUE_LINT_PROJECT=1. For tests/vue-lint/compare.sh, which runs ESLint in the directory of the
// corpus (the tsconfigRootDir). The rules are the directories of tests/rules with an expected.txt,
// as in tests/rules/eslint.cross.config.mjs; the `seyfert/*` rules are those of
// @slipher/eslint-plugin 1.1.0 (build/upstream/seyfert).
import fs from 'node:fs';
import { createRequire } from 'node:module';
import path from 'node:path';
import vueParser from '../../build/upstream/vue-deps/node_modules/vue-eslint-parser/dist/index.cjs';
import tseslint from '../../build/eval/spider-byte/node_modules/typescript-eslint/dist/index.js';
import unicorn from '../../build/eval/spider-byte/node_modules/eslint-plugin-unicorn/index.js';
import stylistic from '../../build/eval/spider-byte/node_modules/@stylistic/eslint-plugin/dist/index.js';
import perfectionist from '../../build/upstream/perfectionist-deps/node_modules/eslint-plugin-perfectionist/dist/index.js';
import marcrock from '../../build/eval/spider-byte/node_modules/@marcrock22/eslint/dist/rules/_.js';

const { plugin: seyfert } = createRequire(import.meta.url)(
  '../../build/upstream/seyfert/node_modules/@slipher/eslint-plugin',
);

const rules = path.join(import.meta.dirname, '..', 'rules');
const ported = fs
  .readdirSync(rules, { recursive: true })
  .filter(file => path.basename(file) === 'expected.txt' && !file.split(path.sep).includes('node_modules'))
  .map(file => path.dirname(file))
  .sort();
// `project: true` is the closest tsconfig.json of each file.
const types = process.env.VUE_LINT_PROJECT === '1' ? { project: true } : { projectService: true };
export default [
  {
    files: ['**/*.vue'],
    languageOptions: {
      parser: vueParser,
      parserOptions: { parser: tseslint.parser, ...types, tsconfigRootDir: process.cwd(), extraFileExtensions: ['.vue'] },
    },
    plugins: { '@typescript-eslint': tseslint.plugin, '@stylistic': stylistic, perfectionist, marcrock, seyfert, unicorn },
    rules: Object.fromEntries(ported.map(rule => [rule, 'error'])),
  },
];
