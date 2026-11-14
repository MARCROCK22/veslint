// unicorn/throw-new-error: an error is created with `new`.
declare const lib: { CustomError: ErrorConstructor; error: () => Error; getErrors(): { TypeError: ErrorConstructor } };
declare const Data: { TaggedError(name: string): unknown };

function f1() {
  throw Error();
}
function f2() {
  throw TypeError('message');
}
function f3() {
  throw lib.CustomError('x');
}
function f4() {
  throw lib.getErrors().TypeError('x');
}
function f5() {
  throw (lib.getErrors().TypeError)('x');
}
function f6() {
  throw(Error)();
}
const e1 = Error?.();
const e2 = HTTP2Error();

// Not reported.
const z1 = new Error();
const z2 = lib.error();
const z3 = lib['CustomError']();
const z4 = Data.TaggedError('x');
const z5 = errorError();
const z6 = HTTP_Error();

// 79.0.0: decorators, template tags, callees and optional chains are not reported; nor a call
// whose type (with type information) has call or construct signatures.
declare function MyError(s: string): (strings: TemplateStringsArray) => Error;
declare function FactoryError(): () => Error;
declare function getErrors(): { Error: ErrorConstructor; nested: { Error: ErrorConstructor } } | undefined;
const y1 = MyError('x')`y`;
const y2 = FactoryError()();
const y3 = FactoryError();
const y4 = lib?.Error();
const y5 = Error?.();
const y6 = getErrors()!.Error('message');
const y7 = getErrors()!.nested.Error('message');
const y8 = (lib.getErrors() as any).Error('message');
