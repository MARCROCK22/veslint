// Reference config for tests/rules/reference.sh: typescript-eslint 8.72.2 (installed in build/eval
// by tests/eval_spider_byte.sh) and, for the `seyfert/*` rules, @slipher/eslint-plugin 1.1.0
// (build/upstream/seyfert, see tests/upstream/README.md). Each rule ported to veslint has a directory
// tests/rules/<rule id>/, and is enabled only on its cases.ts, cases.tsx, cases.vue and cases.svelte
// files: with its default options or, in a subdirectory with options.json, with those. A .vue file is
// read as a Vue project reads it: vue-eslint-parser 10.4.2 with typescript-eslint's parser and
// eslint-plugin-vue 10.12.1's processor (build/upstream/vue-deps); a .svelte file as a Svelte project
// reads it: svelte-eslint-parser 1.10.1 with typescript-eslint's parser and eslint-plugin-svelte
// 3.24.1's processor (build/upstream/svelte-deps).
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
// eslint-plugin-promise 7.3.0 (build/upstream/plugins-new, tests/upstream/README.md).
const promise = createRequire(import.meta.url)('../../build/upstream/plugins-new/node_modules/eslint-plugin-promise');
const plugins = { '@typescript-eslint': tseslint.plugin, '@stylistic': stylistic, perfectionist, marcrock, promise, seyfert, unicorn, vue, svelte };

// The directory of a rule is the one with an expected.txt, and its path is the rule's id
// (`@typescript-eslint/await-thenable`); the files of the packages in a node_modules do not count.
const ported = fs
  .readdirSync(import.meta.dirname, { recursive: true })
  .filter(file => path.basename(file) === 'expected.txt' && !file.split(path.sep).includes('node_modules'))
  .map(file => path.dirname(file))
  .sort();

const withDefaults = ported.flatMap(rule => [
  {
    files: [`**/rules/${rule}/**/cases.ts`, `**/rules/${rule}/**/cases.tsx`],
    languageOptions: {
      parser: tseslint.parser,
      parserOptions: { projectService: true, tsconfigRootDir: import.meta.dirname },
    },
    plugins,
    rules: { [rule]: 'error' },
  },
  {
    files: [`**/rules/${rule}/**/cases.vue`],
    languageOptions: {
      parser: vueParser,
      parserOptions: { parser: tseslint.parser, projectService: true, tsconfigRootDir: import.meta.dirname, extraFileExtensions: ['.vue'] },
    },
    plugins,
    processor: 'vue/vue',
    rules: { [rule]: 'error' },
  },
  {
    files: [`**/rules/${rule}/**/cases.svelte`],
    languageOptions: {
      parser: svelteParser,
      parserOptions: { parser: tseslint.parser, projectService: true, tsconfigRootDir: import.meta.dirname, extraFileExtensions: ['.svelte'] },
    },
    plugins,
    processor: 'svelte/svelte',
    rules: { [rule]: 'error' },
  },
]);

// A subdirectory with options.json (the list of options of the rule) tests other options.
const withOptions = ported.flatMap(rule =>
  fs
    .readdirSync(path.join(import.meta.dirname, rule), { recursive: true })
    .filter(file => path.basename(file) === 'options.json')
    .map(file => ({
      files: [`**/rules/${rule}/${path.dirname(file)}/cases.ts`, `**/rules/${rule}/${path.dirname(file)}/cases.tsx`, `**/rules/${rule}/${path.dirname(file)}/cases.vue`, `**/rules/${rule}/${path.dirname(file)}/cases.svelte`],
      rules: {
        [rule]: [
          'error',
          ...JSON.parse(fs.readFileSync(path.join(import.meta.dirname, rule, file), 'utf8')),
        ],
      },
    })),
);

export default [...withDefaults, ...withOptions];
