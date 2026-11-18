// The ESLint side of tests/svelte-lint/runes (pin.sh): the `rules` and the parserOptions of the
// JSON configuration RUNES_CONFIG names, on .svelte files as a Svelte project lints them
// (svelte-eslint-parser 1.10.1 with typescript-eslint's parser and the project service).
import fs from 'node:fs';
import { createRequire } from 'node:module';
import tseslint from '../../../build/eval/spider-byte/node_modules/typescript-eslint/dist/index.js';

const svelteParser = createRequire(import.meta.url)('../../../build/upstream/svelte-deps/node_modules/svelte-eslint-parser');
const config = JSON.parse(fs.readFileSync(process.env.RUNES_CONFIG, 'utf8'));
export default [
  {
    files: ['**/*.svelte'],
    languageOptions: {
      parser: svelteParser,
      parserOptions: {
        parser: tseslint.parser,
        projectService: true,
        tsconfigRootDir: import.meta.dirname,
        extraFileExtensions: ['.svelte'],
        ...config.languageOptions?.parserOptions,
      },
    },
    plugins: { '@typescript-eslint': tseslint.plugin },
    rules: config.rules,
  },
];
