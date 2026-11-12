// Stands in for vitest while tools/gen_upstream_cases.mjs loads the test files of
// typescript-eslint: a `describe` block runs, so that the RuleTester.run calls inside it are
// recorded; the bodies of `it`/`test` (unit tests of helpers) do not run. `describe.for(table)`
// runs its block once per item of the table, with the item.
//
// While `globalThis.__veslintTests` is an array (the tests of @slipher/eslint-plugin that lint a
// project on disk), `it`/`test` add their test to it, named with the `describe` blocks around it,
// and `expect` checks what the tests of that plugin use: toBe, toContain and toHaveLength, also
// after `.not`.
const noop = () => {};
const chain = run =>
  new Proxy(run, {
    get: (target, key) =>
      key === 'each'
        ? () => chain(run)
        : key === 'for'
          ? table => chain((name, fn) => table.forEach(item => run(name, () => fn?.(item))))
          : key === 'skip' || key === 'todo'
            ? chain(noop)
            : chain(run),
  });

const blocks = [];
export const describe = chain((name, fn) => {
  blocks.push(name);
  try {
    fn?.();
  } finally {
    blocks.pop();
  }
});
export const suite = describe;
export const it = chain((name, fn) => globalThis.__veslintTests?.push({ name: [...blocks, name].join(' > '), fn }));
export const test = it;
export const beforeAll = noop;
export const afterAll = noop;
export const beforeEach = noop;
export const afterEach = noop;

const shown = value => JSON.stringify(value) ?? String(value);
function matchers(actual, negated) {
  const check = (passes, text) => {
    if (passes === negated) throw new Error(`expected ${shown(actual)} ${negated ? 'not ' : ''}${text}`);
  };
  return {
    toBe: expected => check(Object.is(actual, expected), `to be ${shown(expected)}`),
    toContain: item =>
      check(
        actual != null && (typeof actual === 'string' ? actual.includes(item) : [...actual].includes(item)),
        `to contain ${shown(item)}`,
      ),
    toHaveLength: length => check(actual != null && actual.length === length, `to have length ${length}`),
  };
}
const ignored = new Proxy(noop, { get: () => ignored, apply: () => ignored });
export const expect = new Proxy(noop, {
  get: () => ignored,
  apply: (target, self, [actual]) =>
    globalThis.__veslintTests ? { ...matchers(actual, false), not: matchers(actual, true) } : ignored,
});
export const vi = new Proxy({}, { get: () => noop });
export default { describe, it, test, expect, vi };
