// Stands in for @typescript-eslint/rule-tester while tools/gen_upstream_cases.mjs loads the test
// files of typescript-eslint: RuleTester.run records the cases instead of running them.
export const recorded = (globalThis.__veslintRecorded ??= []);

export class RuleTester {
  constructor(config = {}) {
    this.config = config;
  }

  run(name, rule, tests) {
    recorded.push({ name, rule, config: this.config, tests, messages: rule?.meta?.messages ?? {} });
  }

  // A rule of the test file's own (`@rule-tester/<name>` in its cases): not recorded.
  defineRule() {}

  // The test framework hooks of the real class; nothing runs here.
  static afterAll;
  static describe;
  static describeSkip;
  static it;
  static itOnly;
  static itSkip;
}

// The same as the real noFormat: the template text, raw.
export function noFormat(raw, ...keys) {
  return String.raw({ raw }, ...keys);
}
