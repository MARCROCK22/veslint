// Stands in for tests/eslint-compat.ts of eslint-plugin-vue v10.12.1 while
// tools/gen_upstream_cases.mjs loads its test files. Upstream that module hands out
// eslint-compat-utils' RuleTester, ESLint and Linter, which with ESLint 10 are ESLint's own classes:
// here RuleTester.run records the cases instead of running them, and ESLint and Linter are the real
// classes of build/upstream/vue-deps (ESLint 10.15.0), which also record what they lint while
// `globalThis.__veslintLints` is an array (the `it` blocks of comment-directive, block-order and
// no-unused-properties lint with them, and the generator runs those blocks for real).
import path from 'node:path';
import { createRequire } from 'node:module';

export const recorded = (globalThis.__veslintRecorded ??= []);

const VUE_DEPS = path.resolve(import.meta.dir, '../../build/upstream/vue-deps/node_modules');
const requireDependency = createRequire(path.join(VUE_DEPS, 'x.js'));
const eslint = requireDependency('eslint');

export class RuleTester {
  constructor(config = {}) {
    this.config = config;
  }

  run(name, rule, tests) {
    recorded.push({ name, rule, mode: 'vue', config: this.config, tests, messages: rule?.meta?.messages ?? {} });
  }

  // ESLint's RuleTester.only: the case, marked.
  static only(item) {
    return typeof item === 'string' ? { code: item, only: true } : { ...item, only: true };
  }

  static setDefaultConfig() {
    throw new Error('RuleTester.setDefaultConfig is not stubbed (tools/upstream/vue-test.mjs)');
  }
}

// What an `it` block lints: its config as the test gives it (objects, not names: the generator
// names the parsers, plugins and processors), the text, the file and what ESLint gave.
const record = entry => globalThis.__veslintLints?.push(entry);

export class ESLint extends eslint.ESLint {
  constructor(options = {}) {
    super(options);
    this.veslintOptions = options;
  }

  async lintText(code, options = {}) {
    const results = await super.lintText(code, options);
    record({ api: 'ESLint', options: this.veslintOptions, code, filePath: options.filePath, results });
    return results;
  }
}

export class Linter extends eslint.Linter {
  verify(code, config, filename) {
    const messages = super.verify(code, config, filename);
    record({ api: 'Linter', config, code, filename, messages });
    return messages;
  }
}

// ESLint 10: the flat ESLint is ESLint itself.
export const FlatESLint = ESLint;
