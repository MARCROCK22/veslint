declare const v: any;

// Reported.
const a = { ['x']: 1, [1]: 2, ['y']() {}, [0x10]: 3 };
const { ['z']: z } = v;
class B {
  ['m']() {}
  static ['n'] = 1;
  ['p'] = 2;
  static ['prototype2']() {}
  [/* c */ 'q'] = 1;
}
const c = { a:['b'] } as any;
const d = { async['e']() {} };
const e = { get['f']() { return 1; } };

// Not reported.
const f = { [v]: 1, x: 2, [`t`]: 3, [1n]: 4 };
const g = { ['__proto__']: 1 };
class H {
  ['constructor']() {}
  static ['prototype']() {}
  static ['constructor'] = 1;
  ['constructor2'] = 1;
}

// Decorated members, auto-accessors and overloads.
declare function wrap(...a: unknown[]): any;
class Decorated {
  @wrap ['m']() {}
  @wrap
  ['n']() {}
  @wrap ['p'] = 1;
  accessor ['t'] = 1;
  ['u'](): void;
  ['u']() {}
}
abstract class Abstract {
  abstract ['v'](): void;
}
