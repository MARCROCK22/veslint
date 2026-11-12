// Cases of no-unsafe-call (typescript-eslint 8.62.0, no options), with strict.
declare const anyValue: any;
declare const func: Function;
declare const unknownValue: unknown;
declare function normal(): void;
interface MyFunction extends Function { extra: 1 }
declare const mine: MyFunction;
declare const withSignature: Function & (() => void);
declare const constructible: Function & (new () => object);
declare const emptyFn: Function & (() => void) & { typeName: 1 };
declare const genericFn: <T>(x: T) => T;
declare const union: (() => void) | undefined;

function cases() {
  anyValue();
  anyValue.method();
  anyValue?.();
  anyValue.a.b();
  (anyValue)();
  new anyValue();
  new anyValue.SomeClass();
  anyValue`template`;
  anyValue.tagFn`template ${1}`;
  func();
  new func();
  func`x`;
  mine();
  withSignature();
  new withSignature();
  new constructible();
  new emptyFn();
  normal();
  (anyValue as () => void)();
  genericFn(1);
  union?.();
  missing();
  new AlsoMissing();
  void unknownValue;
}
void cases;
