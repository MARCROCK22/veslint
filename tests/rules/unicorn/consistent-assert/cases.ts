// unicorn/consistent-assert: the assert function of `node:assert` is called as `assert.ok(…)`.
import assert from 'node:assert';
import strictAssert from 'assert/strict';
import { default as a2, strict as a3 } from 'assert';
import { strict as notStrict } from 'node:assert/strict';
import type typeOnly from 'node:assert';
import { type default as typeDefault } from 'node:assert';
import other from 'node:assert/other';

assert(true);
strictAssert(1 === 1, 'message');
a2(true);
a3(false);
assert.ok(true);
assert.equal(1, 1);
notStrict(true);
other(true);
function shadowed(assert: (value: unknown) => void) {
  assert(true);
}
const alias = assert;
alias(true);
