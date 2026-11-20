// Every rule veslint has, with its default options, on .vue files as a Vue project lints them:
// vue-eslint-parser 10.4.2 with typescript-eslint's parser for the scripts and the types of the
// project service (extraFileExtensions ['.vue']), or of `parserOptions.project` with
// VUE_LINT_PROJECT=1. For tests/vue-lint/compare.sh and pin.sh, which run ESLint in the directory
// of the files (the tsconfigRootDir). The rules are the directories of tests/rules with an
// expected.txt, as in tests/rules/eslint.cross.config.mjs, or those of the JSON file
// VUE_LINT_RULES names (a `rules` section); the `seyfert/*` rules are those of
// @slipher/eslint-plugin 1.1.0 (build/upstream/seyfert), the `vue/*` rules those of eslint-plugin-vue
// 10.12.1 (build/upstream/vue-deps).
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
// eslint-plugin-vue 10.12.1, for the vue/* rules, with its processor (as its configurations set it).
const vue = createRequire(import.meta.url)('../../build/upstream/vue-deps/node_modules/eslint-plugin-vue');

// @eslint-community/eslint-plugin-eslint-comments 4.8.1, eslint-plugin-promise 7.3.0 and
// eslint-plugin-regexp 3.3.3 (build/upstream/plugins-new).
const eslintComments = createRequire(import.meta.url)('../../build/upstream/plugins-new/node_modules/@eslint-community/eslint-plugin-eslint-comments');
const promise = createRequire(import.meta.url)('../../build/upstream/plugins-new/node_modules/eslint-plugin-promise');
const regexp = createRequire(import.meta.url)('../../build/upstream/plugins-new/node_modules/eslint-plugin-regexp');

const rules = path.join(import.meta.dirname, '..', 'rules');
// The options of the rules whose schema needs some (tests/rules/required_options.json).
const required = JSON.parse(fs.readFileSync(path.join(import.meta.dirname, '..', 'rules', 'required_options.json'), 'utf8'));
const ported = process.env.VUE_LINT_RULES
  ? Object.keys(JSON.parse(fs.readFileSync(process.env.VUE_LINT_RULES, 'utf8')).rules)
  : fs
      .readdirSync(rules, { recursive: true })
      // The svelte/* rules belong to another plugin, which this configuration does not load.
      .filter(file => path.basename(file) === 'expected.txt' && !file.split(path.sep).includes('node_modules') && file.split(path.sep)[0] !== 'svelte')
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
    plugins: { '@typescript-eslint': tseslint.plugin, '@stylistic': stylistic, perfectionist, marcrock, promise, regexp, seyfert, unicorn, vue, '@eslint-community/eslint-comments': eslintComments },
    processor: 'vue/vue',
    rules: Object.fromEntries(ported.map(rule => [rule, required[rule] ? ['error', ...required[rule]] : 'error'])),
  },
];
