// Files in none of the projects typescript-eslint takes the types from (tests/run.sh): ESLint
// reports each as a fatal parsing error and lints the others. `service` gets the types from the
// project service: b.ts is in no tsconfig; nested/y.ts is in its parent's tsconfig, not in the
// closest one; solution/s.ts is in a project the closest tsconfig references; .generated/g.d.ts is
// in none. `project` gets them from the program of `parserOptions.project`. In `default-project`,
// allowDefaultProject matches d-in.ts, which the tsconfig has too, and d-out.ts, which only the
// default project has (veslint does not lint it, with a warning), but not out.ts.
import tseslint from '../../build/eval/spider-byte/node_modules/typescript-eslint/dist/index.js';

const rules = { 'prefer-const': 'error', '@typescript-eslint/no-floating-promises': 'error' };
const plugins = { '@typescript-eslint': tseslint.plugin };
export default [
  {
    files: ['service/**/*.ts'],
    languageOptions: { parser: tseslint.parser, parserOptions: { projectService: true, tsconfigRootDir: import.meta.dirname } },
    plugins,
    rules,
  },
  {
    files: ['project/**/*.ts'],
    languageOptions: { parser: tseslint.parser, parserOptions: { project: './project/tsconfig.json', tsconfigRootDir: import.meta.dirname } },
    plugins,
    rules,
  },
  {
    files: ['default-project/**/*.ts'],
    languageOptions: {
      parser: tseslint.parser,
      parserOptions: { projectService: { allowDefaultProject: ['default-project/d-*.ts'] }, tsconfigRootDir: import.meta.dirname },
    },
    plugins,
    rules,
  },
];
