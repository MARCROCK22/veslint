// Stands in for eslint-vitest-rule-tester 3.1.0 while tools/gen_upstream_cases.mjs loads the test
// files of eslint-plugin-perfectionist v5.13.0: `createRuleTester({name, rule, languageOptions})`
// gives `valid(…)` and `invalid(…)`, which record their case (normalized as the tester's
// normalizeTestCase and normalizeCaseError do: a string error is a messageId, the case's
// `parserOptions` and `parser` go to its languageOptions, options that are not a list are the one
// option) instead of running it. The `it` blocks that call them are run by the generator. The
// tester of these tests makes up to 10 more passes of fixes after the first (`recursive`), and the
// output it checks is the last one. Without a parser a case is espree's (JavaScript).
export const recorded = (globalThis.__veslintRecorded ??= []);

function normalizeCase(c) {
  const test = typeof c === 'string' ? { code: c } : { ...c };
  if (test.parserOptions || test.parser) {
    test.languageOptions = { ...test.languageOptions };
    if (test.parserOptions) {
      test.languageOptions.parserOptions = { ...test.parserOptions, ...test.languageOptions.parserOptions };
      delete test.parserOptions;
    }
    if (test.parser) {
      test.languageOptions.parser ??= test.parser;
      delete test.parser;
    }
  }
  if (test.options !== undefined && !Array.isArray(test.options)) test.options = [test.options];
  if (Array.isArray(test.errors)) {
    test.errors = test.errors.map(error => (typeof error === 'string' ? { messageId: error } : error));
  } else if (test.errors !== undefined && typeof test.errors !== 'number') {
    test.errors = [typeof test.errors === 'string' ? { messageId: test.errors } : test.errors];
  }
  if (typeof test.output === 'function' || typeof test.errors === 'function') {
    throw new Error(`a case with an output or errors function (a snapshot) is not handled: ${test.code}`);
  }
  return test;
}

export function createRuleTester(options) {
  const languageOptions = { ...options.languageOptions };
  if (options.parser) languageOptions.parser = options.parser;
  if (options.parserOptions) languageOptions.parserOptions = { ...options.parserOptions, ...languageOptions.parserOptions };
  const run = {
    name: options.name,
    rule: options.rule,
    mode: 'perfectionist',
    config: { languageOptions, settings: options.settings },
    tests: { valid: [], invalid: [] },
    messages: {},
  };
  recorded.push(run);
  // The promise of a case can take it back: `expect(valid(…)).rejects.toThrow()` is a case that
  // ESLint must refuse (invalid options or settings), not one to check (tools/upstream/vitest.mjs).
  const record = (list, c) => {
    const test = normalizeCase(c);
    list.push(test);
    const promise = Promise.resolve();
    promise.__veslintTakeBack = () => {
      const index = list.indexOf(test);
      if (index >= 0) list.splice(index, 1);
    };
    return promise;
  };
  return {
    valid: c => record(run.tests.valid, c),
    invalid: c => record(run.tests.invalid, c),
  };
}

// The `unindent` the tester exports.
export function unindent(str) {
  const lines = (typeof str === 'string' ? str : str[0]).split('\n');
  const whitespaceLines = lines.map(line => /^\s*$/.test(line));
  const commonIndent = lines.reduce((min, line, idx) => {
    if (whitespaceLines[idx]) return min;
    const indent = line.match(/^\s*/)?.[0].length;
    return indent === undefined ? min : Math.min(min, indent);
  }, Number.POSITIVE_INFINITY);
  let emptyLinesHead = 0;
  while (emptyLinesHead < lines.length && whitespaceLines[emptyLinesHead]) emptyLinesHead++;
  let emptyLinesTail = 0;
  while (emptyLinesTail < lines.length && whitespaceLines[lines.length - emptyLinesTail - 1]) emptyLinesTail++;
  return lines.slice(emptyLinesHead, lines.length - emptyLinesTail).map(line => line.slice(commonIndent)).join('\n');
}
export const $ = unindent;

// test/rules/build-oxlint-rule-tester.ts: the same cases run with oxlint's RuleTester, which is
// not ESLint: not recorded.
export function buildOxlintRuleTester() {
  return { run() {} };
}

// test/utils/validate-rule-json-schema.ts: a unit test of the schema, not a case.
export async function validateRuleJsonSchema() {}
