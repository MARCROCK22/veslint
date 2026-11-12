// ESLint configuration of tests/directives: the rules of rules.json, the same ones veslint gets
// with --config, so both tools agree on which directive comments are unused.
import fs from 'node:fs';
import path from 'node:path';
import tseslint from '../../build/eval/spider-byte/node_modules/typescript-eslint/dist/index.js';

const { rules } = JSON.parse(fs.readFileSync(path.join(import.meta.dirname, 'rules.json'), 'utf8'));

export default [
  {
    files: ['**/*.ts'],
    languageOptions: {
      parser: tseslint.parser,
      parserOptions: { projectService: true, tsconfigRootDir: import.meta.dirname },
    },
    plugins: { '@typescript-eslint': tseslint.plugin },
    rules,
  },
];
