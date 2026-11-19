// Stands in for @eslint/css while tools/gen_upstream_cases.mjs loads the tests of
// @eslint-community/eslint-plugin-eslint-comments: their cases of the css/css language name it as a
// plugin, and are skipped (veslint lints TypeScript only).
export default { meta: { name: '@eslint/css' }, languages: {}, rules: {} };
