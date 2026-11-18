// Stands in for tests/utils/eslint-compat.ts of eslint-plugin-svelte 3.24.1 (and for the `eslint`
// module of tests/src/rules/comment-directive.ts) while tools/gen_upstream_cases.mjs loads its test
// files. Upstream eslint-compat.ts hands out ESLint's RuleTester: here RuleTester.run records the
// cases instead of running them. comment-directive.ts lints with the ESLint class it gets from
// `loadESLint`: the real class of build/upstream/svelte-deps (ESLint 10.15.0), which also records
// what it lints while `globalThis.__veslintLints` is an array (the generator runs those `it` blocks
// for real, and the `before` hooks with them).
import path from 'node:path';
import { createRequire } from 'node:module';

export const recorded = (globalThis.__veslintRecorded ??= []);

const SVELTE_DEPS = path.resolve(import.meta.dir, '../../build/upstream/svelte-deps/node_modules');
const requireDependency = createRequire(path.join(SVELTE_DEPS, 'x.js'));
const eslint = requireDependency('eslint');

export class RuleTester {
  constructor(config = {}) {
    this.config = config;
  }

  run(name, rule, tests) {
    recorded.push({ name, rule, mode: 'svelte', config: this.config, tests, messages: rule?.meta?.messages ?? {} });
  }

  static only(item) {
    return typeof item === 'string' ? { code: item, only: true } : { ...item, only: true };
  }

  static setDefaultConfig() {
    throw new Error('RuleTester.setDefaultConfig is not stubbed (tools/upstream/svelte-test.mjs)');
  }
}

// What an `it` block lints: the options of the ESLint instance as the test gives them (objects,
// not names: the generator names the parsers, plugins and processors), the text, the file and what
// ESLint gave.
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

// ESLint 10's loadESLint: the flat ESLint class, here the recording one.
export async function loadESLint() {
  return ESLint;
}

// mocha's `before`: it runs before the `it` blocks of its `describe`. In comment-directive.ts each
// one comes first in its block (it makes the ESLint instance the block's tests use), so it joins
// the tests the generator runs, in the place it has.
export function before(fn) {
  globalThis.__veslintTests?.push({ name: '(before)', fn, hook: true });
}
