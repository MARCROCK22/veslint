// A flat configuration with what veslint takes from ESLint itself: global ignores, rules and
// options per folder, and linterOptions. It is used from this directory (`--config` makes the
// patterns relative to the working directory, as in `eslint -c`).
import tseslint from '../../build/eval/spider-byte/node_modules/typescript-eslint/dist/index.js';

export default [
  { ignores: ['ignored/**', '**/*.gen.ts'] },
  {
    files: ['**/*.ts'],
    languageOptions: {
      parser: tseslint.parser,
      parserOptions: { projectService: true, tsconfigRootDir: import.meta.dirname },
    },
    plugins: { '@typescript-eslint': tseslint.plugin },
    rules: {
      '@typescript-eslint/no-floating-promises': 'error',
      '@typescript-eslint/await-thenable': 'warn',
    },
  },
  // A rule veslint does not have: whether a directive without rules is unused there cannot be
  // known, so the file of this folder has none.
  { files: ['other/**'], rules: { 'no-debugger': 'error', 'no-console': 'warn' } },
  // The directive comments that name those rules, one of veslint's that is off, and others.
  {
    files: ['neighbours/**'],
    rules: { 'no-debugger': 'error', 'no-console': 'warn', 'no-alert': 'off', '@typescript-eslint/await-thenable': 'off' },
  },
  {
    files: ['strict/**/*.ts'],
    rules: {
      '@typescript-eslint/await-thenable': 'error',
      '@typescript-eslint/no-array-delete': 'error',
      '@typescript-eslint/no-floating-promises': ['error', { ignoreVoid: false }],
    },
  },
  {
    files: ['quiet/**'],
    linterOptions: { reportUnusedDisableDirectives: 'off' },
    rules: { '@typescript-eslint/no-floating-promises': 'off' },
  },
  { files: ['locked/**'], linterOptions: { noInlineConfig: true } },
  { files: ['unused-error/**'], linterOptions: { reportUnusedDisableDirectives: 'error' } },
  // reportUnusedInlineConfigs: a comment that configures a rule as the configuration already does.
  {
    files: ['unused-inline/**'],
    linterOptions: { reportUnusedInlineConfigs: 'error' },
    rules: {
      curly: ['error', 'multi'],
      eqeqeq: 'warn',
      'no-console': 'off',
      'no-unused-vars': ['error', { args: 'none' }],
      '@typescript-eslint/no-floating-promises': ['error', { ignoreVoid: false }],
      '@typescript-eslint/no-array-delete': 'error',
      '@typescript-eslint/dot-notation': ['warn', { allowKeywords: true }],
    },
  },
  { files: ['unused-inline/warned.ts'], linterOptions: { reportUnusedInlineConfigs: 'warn' } },
  // `from: "file"` type specifiers are relative to the current directory of the program, which
  // depends on how the parser gets the types: the directory of the tsconfig with the project
  // service, and the one ESLint runs in with `project`. Each folder allows a type by its path from
  // the one directory, another by its path from the other, and a third declared out of the folder.
  {
    files: ['program-dir/project/**'],
    languageOptions: { parserOptions: { projectService: false, project: ['./program-dir/project/tsconfig.json'] } },
    rules: {
      '@typescript-eslint/await-thenable': 'off',
      '@typescript-eslint/no-floating-promises': [
        'error',
        {
          allowForKnownSafePromises: [
            { from: 'file', name: 'ByWorkingDirectory', path: 'program-dir/project/types.ts' },
            { from: 'file', name: 'ByProjectDirectory', path: 'types.ts' },
            { from: 'file', name: 'Shared' },
          ],
        },
      ],
    },
  },
  {
    files: ['program-dir/service/**'],
    rules: {
      '@typescript-eslint/await-thenable': 'off',
      '@typescript-eslint/no-floating-promises': [
        'error',
        {
          allowForKnownSafePromises: [
            { from: 'file', name: 'ByWorkingDirectory', path: 'program-dir/service/types.ts' },
            { from: 'file', name: 'ByProjectDirectory', path: 'types.ts' },
            { from: 'file', name: 'Shared' },
          ],
        },
      ],
    },
  },
  // The tsconfig `parserOptions.project` names, not the closest one: the types of this folder come
  // from tsconfig.lint.json (strict), not from the tsconfig.json beside it (not strict).
  {
    files: ['named-project/**'],
    languageOptions: { parserOptions: { projectService: false, project: ['./named-project/tsconfig.lint.json'] } },
    rules: { '@typescript-eslint/await-thenable': 'off', '@typescript-eslint/no-unnecessary-condition': 'error' },
  },
  // The globals of a file: those of its ecmaVersion and of `globals`, which a comment may change.
  {
    files: ['globals/**'],
    languageOptions: { ecmaVersion: 2019, globals: { parseInt: 'off', parseFloat: 'off', Number: 'off', isNaN: false } },
    rules: { '@typescript-eslint/prefer-find': 'error' },
  },
  // What typescript-eslint's scope manager takes from the configuration: `globals` of any name,
  // the sourceType and the `lib` of the parser options.
  {
    files: ['scopes/**'],
    languageOptions: { globals: { configUnused: 'readonly', configUsed: 'writable', configOff: 'off', Map: 'off' } },
    rules: {
      '@typescript-eslint/naming-convention': [
        'error',
        { selector: ['class', 'variable', 'function'], modifiers: ['unused'], format: null, leadingUnderscore: 'require' },
      ],
    },
  },
  { files: ['scopes/script.ts'], languageOptions: { sourceType: 'script' } },
  { files: ['scopes/commonjs.ts'], languageOptions: { sourceType: 'commonjs' } },
  { files: ['scopes/lib.ts'], languageOptions: { parserOptions: { lib: ['es5'] } } },
];
