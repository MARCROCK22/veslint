// Stands in for `node:test` while tools/gen_upstream_cases.mjs loads the test files of
// eslint-plugin-unicorn: besides RuleTester's cases they have tests of their own (a Linter that fixes
// in several passes…), which are not cases of the rule and are left out.
const ignore = () => {};
export default ignore;
export const test = ignore;
export const describe = ignore;
export const it = ignore;
