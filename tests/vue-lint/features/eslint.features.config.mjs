// The ESLint side of tests/vue-lint/features (pin.sh): the `rules` and the parserOptions (vueFeatures)
// of the JSON configuration FEATURES_CONFIG names, on .vue files as a Vue project lints them
// (vue-eslint-parser 10.4.2 with typescript-eslint's parser and the project service, and
// eslint-plugin-vue 10.12.1 with its processor).
import fs from 'node:fs';
import { createRequire } from 'node:module';
import vueParser from '../../../build/upstream/vue-deps/node_modules/vue-eslint-parser/dist/index.cjs';
import tseslint from '../../../build/eval/spider-byte/node_modules/typescript-eslint/dist/index.js';

const vue = createRequire(import.meta.url)('../../../build/upstream/vue-deps/node_modules/eslint-plugin-vue');
const config = JSON.parse(fs.readFileSync(process.env.FEATURES_CONFIG, 'utf8'));
export default [
  {
    files: ['**/*.vue'],
    languageOptions: {
      parser: vueParser,
      parserOptions: {
        parser: tseslint.parser,
        projectService: true,
        tsconfigRootDir: import.meta.dirname,
        extraFileExtensions: ['.vue'],
        ...config.languageOptions?.parserOptions,
      },
    },
    plugins: { '@typescript-eslint': tseslint.plugin, vue },
    processor: 'vue/vue',
    rules: config.rules,
  },
];
