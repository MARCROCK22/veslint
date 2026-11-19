// Stands in for ESLint's RuleTester while tools/gen_upstream_cases.mjs loads the test files of
// eslint-plugin-promise v7.3.0: their __tests__/rule-tester.js requires `RuleTester` from `eslint`
// (this module, there), converts the eslintrc-style configuration of the tester and of each case to
// languageOptions as it does for ESLint 10, and calls `run`, which records the rule's cases instead
// of running them.
export const recorded = (globalThis.__veslintRecorded ??= []);

export class RuleTester {
  constructor(config = {}) {
    this.config = config;
  }

  run(name, rule, tests) {
    recorded.push({ name, rule, config: this.config, tests, messages: rule?.meta?.messages ?? {} });
  }

  static only(item) {
    return typeof item === 'string' ? { code: item, only: true } : { ...item, only: true };
  }
}
