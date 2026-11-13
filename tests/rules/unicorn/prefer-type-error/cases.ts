// unicorn/prefer-type-error: an `Error` thrown alone in a type check is a `TypeError`.
declare const x: unknown;
declare const _: { isString(v: unknown): boolean; lang: { isNumber(v: unknown): boolean } };
declare class Foo {}

if (typeof x !== 'string') {
  throw new Error('x must be a string');
}
if (!Array.isArray(x)) {
  throw new Error('array');
}
if (!(x instanceof Foo)) {
  throw new Error();
}
if (_.isString(x) && _.lang.isNumber(x)) {
  throw new Error('both');
}
if (isNaN(x as number)) {
  throw new Error('nan');
}
if (typeof x === 'number') {
} else {
  throw new Error('else');
}
function f() {
  if (Number.isFinite(x) || typeof x === 'bigint') {
    throw new Error('finite');
  }
}

// Not reported.
if (x instanceof TypeError) {
  throw new Error('error');
}
if (typeof x !== 'string') {
  console.log(x);
  throw new Error('not lone');
}
if (x === 1) {
  throw new Error('not a type check');
}
if (Array.isArray()) {
  throw new Error('no argument');
}
if (typeof x !== 'string') {
  throw new TypeError('already');
}
if (typeof x !== 'string') throw new Error('no block');
