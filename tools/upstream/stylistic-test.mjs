// Stands in for shared/test-utils (`#test`) of eslint-stylistic v5.10.0 while
// tools/gen_upstream_cases.mjs loads the test files of @stylistic/eslint-plugin: `run(…)` of
// eslint-vitest-rule-tester 3.1.0 records the cases instead of running them, each normalized as
// its normalizeTestCase and normalizeCaseError normalize them (a string error is a messageId; the
// case's `parserOptions` and `parser` go to its languageOptions; options that are not a list are
// the one option). `lang` picks the parser as runner.ts does: typescript-eslint's (`ts`, the
// default) or espree (`js`); JSON, CSS and Markdown cases are skipped.
export const recorded = (globalThis.__veslintRecorded ??= []);

// unindent of @antfu/utils 9.3.0, which eslint-vitest-rule-tester exports as `$`.
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

// shared/test-utils/index.ts: `gte(ESLint.version, '10.0.0')`, with ESLint 10.15.0.
export const skipBabel = true;

// The parsers, by name only: a case that names one keeps its name.
export const parsers = {
  typescript: { meta: { name: 'typescript-eslint/parser' } },
  babelFlow: { meta: { name: 'babel-flow' } },
};

// shared/test-utils/parsers-flow.ts.
export const languageOptionsForBabelFlow = { parser: parsers.babelFlow, parserOptions: {} };

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

export function run(options) {
  const lang = options.lang ?? 'ts';
  const languageOptions = { ...options.languageOptions };
  if (options.parserOptions) languageOptions.parserOptions = { ...options.parserOptions, ...languageOptions.parserOptions };
  if (lang === 'ts') languageOptions.parser = parsers.typescript;
  recorded.push({
    name: options.name,
    rule: options.rule,
    mode: 'stylistic',
    lang,
    config: { languageOptions, settings: options.settings },
    tests: { valid: (options.valid ?? []).map(normalizeCase), invalid: (options.invalid ?? []).map(normalizeCase) },
    messages: {},
  });
}
