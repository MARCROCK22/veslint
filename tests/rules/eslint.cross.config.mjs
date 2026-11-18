// All the ported rules, with their default options, on every fixture of tests/rules: for
// tests/rules/cross.sh, which compares what ESLint and veslint report for a rule on the fixtures of
// the other rules. The `seyfert/*` rules are those of @slipher/eslint-plugin 1.1.0
// (build/upstream/seyfert).
import fs from 'node:fs';
import { createRequire } from 'node:module';
import path from 'node:path';
import tseslint from '../../build/eval/spider-byte/node_modules/typescript-eslint/dist/index.js';
import unicorn from '../../build/eval/spider-byte/node_modules/eslint-plugin-unicorn/index.js';
import stylistic from '../../build/eval/spider-byte/node_modules/@stylistic/eslint-plugin/dist/index.js';
import perfectionist from '../../build/upstream/perfectionist-deps/node_modules/eslint-plugin-perfectionist/dist/index.js';
import marcrock from '../../build/eval/spider-byte/node_modules/@marcrock22/eslint/dist/rules/_.js';
import vueParser from '../../build/upstream/vue-deps/node_modules/vue-eslint-parser/dist/index.cjs';
// eslint-plugin-svelte's rules that read types load TypeScript 6.0.3 (see the module).
import './svelte/typescript6.mjs';

const { plugin: seyfert } = createRequire(import.meta.url)(
  '../../build/upstream/seyfert/node_modules/@slipher/eslint-plugin',
);
const vue = createRequire(import.meta.url)('../../build/upstream/vue-deps/node_modules/eslint-plugin-vue');
const svelteParser = createRequire(import.meta.url)('../../build/upstream/svelte-deps/node_modules/svelte-eslint-parser');
const svelte = createRequire(import.meta.url)('../../build/upstream/svelte-deps/node_modules/eslint-plugin-svelte');
const plugins = { '@typescript-eslint': tseslint.plugin, '@stylistic': stylistic, perfectionist, marcrock, seyfert, unicorn, vue, svelte };

const root = import.meta.dirname;
// The directory of a rule is the one with an expected.txt, and its path is the rule's id; the files
// of the packages in a node_modules do not count.
// The options of the rules whose schema needs some (tests/rules/required_options.json).
const required = JSON.parse(fs.readFileSync(path.join(root, 'required_options.json'), 'utf8'));
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
    plugins,
    rules: Object.fromEntries(ported.map(rule => [rule, required[rule] ? ['error', ...required[rule]] : 'error'])),
  },
  // The .vue fixtures (of the vue/* rules), as a Vue project reads them: vue-eslint-parser 10.4.2 with
  // typescript-eslint's parser and eslint-plugin-vue 10.12.1's processor.
  {
    files: ['**/cases.vue'],
    languageOptions: {
      parser: vueParser,
      parserOptions: { parser: tseslint.parser, projectService: true, tsconfigRootDir: root, extraFileExtensions: ['.vue'] },
    },
    plugins,
    processor: 'vue/vue',
    rules: Object.fromEntries(ported.map(rule => [rule, required[rule] ? ['error', ...required[rule]] : 'error'])),
  },
  // The .svelte fixtures (of the svelte/* rules), as a Svelte project reads them: svelte-eslint-parser
  // 1.10.1 with typescript-eslint's parser and eslint-plugin-svelte 3.24.1's processor.
  {
    files: ['**/cases.svelte'],
    languageOptions: {
      parser: svelteParser,
      parserOptions: { parser: tseslint.parser, projectService: true, tsconfigRootDir: root, extraFileExtensions: ['.svelte'] },
    },
    plugins,
    processor: 'svelte/svelte',
    rules: Object.fromEntries(ported.map(rule => [rule, required[rule] ? ['error', ...required[rule]] : 'error'])),
  },
];
