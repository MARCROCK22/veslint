// A function as parserOptions.svelteConfig.compilerOptions.runes, which svelte-eslint-parser and
// eslint-plugin-svelte (valid-compile) call with the absolute path of each .svelte file: runes for
// plain.svelte, not for legacy.svelte (the same code), and <svelte:options runes> wins for
// options.svelte. veslint's resolver calls it per file (pin.sh pins it as `function: `).
import { createRequire } from 'node:module';
import path from 'node:path';
import tseslint from '../../../build/eval/spider-byte/node_modules/typescript-eslint/dist/index.js';

const require = createRequire(import.meta.url);
const svelteParser = require('../../../build/upstream/svelte-deps/node_modules/svelte-eslint-parser');
const svelte = require('../../../build/upstream/svelte-deps/node_modules/eslint-plugin-svelte');
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
        svelteConfig: {
          compilerOptions: {
            runes: ({ filename }) => path.isAbsolute(filename) && !path.basename(filename).startsWith('legacy'),
          },
        },
      },
    },
    plugins: { '@typescript-eslint': tseslint.plugin, svelte },
    rules: {
      '@typescript-eslint/no-unsafe-assignment': 'error',
      '@typescript-eslint/no-unsafe-call': 'error',
      'prefer-const': 'error',
      'svelte/valid-compile': 'error',
    },
  },
];
