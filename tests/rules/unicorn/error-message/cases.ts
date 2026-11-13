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
