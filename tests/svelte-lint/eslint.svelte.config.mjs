// Every rule veslint has, with its default options, on .svelte files as a Svelte project lints
// them: svelte-eslint-parser 1.10.1 with typescript-eslint's parser (an object: every file is
// TypeScript) and the types of the project service (extraFileExtensions ['.svelte']), or of
// `parserOptions.project` with SVELTE_LINT_PROJECT=1. For tests/svelte-lint/compare.sh and pin.sh,
// which run ESLint in the directory of the files (the tsconfigRootDir). The rules are the
// directories of tests/rules with an expected.txt, as in tests/rules/eslint.cross.config.mjs, or
// those of the JSON file SVELTE_LINT_RULES names (a `rules` section); the `seyfert/*` rules are
// those of @slipher/eslint-plugin 1.1.0 (build/upstream/seyfert), the `vue/*` rules those of
// eslint-plugin-vue 10.12.1 (build/upstream/vue-deps).
import fs from 'node:fs';
import { createRequire } from 'node:module';
import path from 'node:path';
import tseslint from '../../build/eval/spider-byte/node_modules/typescript-eslint/dist/index.js';
import unicorn from '../../build/eval/spider-byte/node_modules/eslint-plugin-unicorn/index.js';
import stylistic from '../../build/eval/spider-byte/node_modules/@stylistic/eslint-plugin/dist/index.js';
import perfectionist from '../../build/upstream/perfectionist-deps/node_modules/eslint-plugin-perfectionist/dist/index.js';
import marcrock from '../../build/eval/spider-byte/node_modules/@marcrock22/eslint/dist/rules/_.js';

const require = createRequire(import.meta.url);
const svelteParser = require('../../build/upstream/svelte-deps/node_modules/svelte-eslint-parser');
const { plugin: seyfert } = require('../../build/upstream/seyfert/node_modules/@slipher/eslint-plugin');
const vue = require('../../build/upstream/vue-deps/node_modules/eslint-plugin-vue');

const rules = path.join(import.meta.dirname, '..', 'rules');
const ported = process.env.SVELTE_LINT_RULES
  ? Object.keys(JSON.parse(fs.readFileSync(process.env.SVELTE_LINT_RULES, 'utf8')).rules)
  : fs
      .readdirSync(rules, { recursive: true })
      .filter(file => path.basename(file) === 'expected.txt' && !file.split(path.sep).includes('node_modules'))
      .map(file => path.dirname(file))
      .filter(rule => !rule.startsWith('svelte' + path.sep))
      .sort();
// `project: true` is the closest tsconfig.json of each file.
const types = process.env.SVELTE_LINT_PROJECT === '1' ? { project: true } : { projectService: true };
export default [
  {
    files: ['**/*.svelte'],
    languageOptions: {
      parser: svelteParser,
      parserOptions: { parser: tseslint.parser, ...types, tsconfigRootDir: process.cwd(), extraFileExtensions: ['.svelte'] },
    },
    plugins: { '@typescript-eslint': tseslint.plugin, '@stylistic': stylistic, perfectionist, marcrock, seyfert, unicorn, vue },
    rules: Object.fromEntries(ported.map(rule => [rule, 'error'])),
  },
];
