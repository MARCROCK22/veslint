// unicorn/error-message: a built-in error gets a message, a string that is not empty.
declare const args: string[];
declare function message(): string;

const e1 = new Error();
const e2 = Error();
const e3 = new TypeError('');
const e4 = new RangeError(``);
const e5 = new Error([]);
const e6 = new Error({});
const e7 = new Error(123);
const e8 = new AggregateError([]);
const e9 = new AggregateError([], '');
const empty = '';
const e10 = new SyntaxError(empty);
const e11 = new URIError(true ? 'a' : 1);
const e12 = new Error(null);
// TypeScript: an assertion is looked through by the constant evaluation.
const e13 = new Error('' as string);

// Not reported.
const z1 = new Error('message');
const z2 = new Error(message());
const z3 = new Error(...args);
const z4 = new AggregateError(...[[], '']);
const z5 = new AggregateError([], ...args);
function shadowed(Error: ErrorConstructor) {
  return new Error();
}
const z7 = new CustomError();

// 79.0.0: a branch or a member read that may change is evaluated only when it is safe.
function m1() {
  const modes = new Set(['foo']);
  modes.clear();
  new Error(modes.size ? {} : 'ok');
  new Error((modes.size ? {} : 'ok') as any);
  new Error(modes.size || 'ok');
}
function m2() {
  let condition = true;
  condition = false;
  new Error(condition ? {} : 'ok');
}
function m3() {
  const object = { value: 1 };
  Object.defineProperty(object, 'value', { get() { return 'message'; } });
  new Error(object.value);
  new Error([object.value][0]);
  new Error(Object.freeze(object).value);
}
function m4(Object: ObjectConstructor) {
  new Error(Object.freeze({ value: 1 }).value);
}
function m5() {
  const object = { value: 1 };
  new Error(Object.freeze(object).value);
  new Error(Object.freeze({ value: 1 }).value);
  new Error(Object.freeze({ value: '' }).value);
  const frozen = Object.freeze({ value: 2 }).value;
  new Error(frozen);
  const constant = true;
  new Error(constant ? {} : 'ok');
  new Error(false);
  new Error(Math.PI);
  new Error('abc'.length);
  new Error([1, 2][0]);
}
