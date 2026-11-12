// ESLint configuration of tests/config-errors: the rules of the JSON file the RULES variable
// names, the same ones veslint gets with --config. Each of those files has something ESLint does
// not take, and the .txt next to it is what the eslint command prints for it.
import fs from 'node:fs';
import path from 'node:path';
import tseslint from '../../build/eval/spider-byte/node_modules/typescript-eslint/dist/index.js';

const { rules } = JSON.parse(fs.readFileSync(path.join(import.meta.dirname, process.env.RULES), 'utf8'));

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
