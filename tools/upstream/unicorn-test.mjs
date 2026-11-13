// Stands in for test/utils/test.js of eslint-plugin-unicorn while tools/gen_upstream_cases.mjs loads
// its test files: `test(…)` (eslint-ava-rule-tester, cases with their errors), `test.snapshot(…)`
// (cases whose errors are in an AVA snapshot) and `test.typescript(…)`/`test.vue(…)` (with that
// parser) record their cases instead of running them. normalizeTestCase and avoidTestTitleConflict
// are those of v64.0.0.
import path from 'node:path';
import url from 'node:url';

export const recorded = (globalThis.__veslintRecorded ??= []);

// The parsers of test/utils/parsers.js, by name only: a case that names one keeps its name.
export const parsers = {
  typescript: { name: 'typescript', meta: { name: 'typescript' } },
  vue: { name: 'vue', meta: { name: 'vue' } },
};

export function normalizeTestCase(testCase) {
  return typeof testCase === 'string' ? { code: testCase } : testCase;
}

// https://github.com/tc39/proposal-array-is-template-object
const isTemplateObject = value => Array.isArray(value?.raw);
const cooked = (raw, ...substitutions) => String.raw({ raw }, ...substitutions);

function only(...arguments_) {
  if (isTemplateObject(arguments_[0])) return { code: cooked(...arguments_), only: true };
  return { ...normalizeTestCase(arguments_[0]), only: true };
}

export function getTester(importMeta) {
  const ruleId = path.basename(url.fileURLToPath(importMeta.url), '.js');
  const record = (mode, tests, parser) => {
    const { testerOptions = {}, valid = [], invalid = [] } = tests;
    const languageOptions = { ...testerOptions.languageOptions };
    if (parser) languageOptions.parser = parser;
    recorded.push({
      name: ruleId,
      mode,
      config: { ...testerOptions, languageOptions },
      tests: { valid: valid.map(normalizeTestCase), invalid: invalid.map(normalizeTestCase) },
      messages: {},
    });
  };
  const test = tests => record('test', tests);
  test.snapshot = tests => record('snapshot', tests);
  test.only = only;
  for (const parser of Object.values(parsers)) {
    test[parser.name] = tests => record('test', tests, parser);
  }
  return { ruleId, rule: undefined, test };
}

const addComment = (testCase, comment) => {
  testCase = normalizeTestCase(testCase);
  const { code, output } = testCase;
  const fixedTest = { ...testCase, code: `${code}\n/* ${comment} */` };
  if (Object.hasOwn(fixedTest, 'output') && typeof output === 'string') fixedTest.output = `${output}\n/* ${comment} */`;
  return fixedTest;
};

export const avoidTestTitleConflict = (tests, comment) => {
  const { valid, invalid } = tests;
  return {
    ...tests,
    valid: valid.map(testCase => addComment(testCase, comment)),
    invalid: invalid.map(testCase => addComment(testCase, comment)),
  };
};
