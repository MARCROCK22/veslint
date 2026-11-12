// Cases of no-unsafe-assignment (typescript-eslint 8.62.0, no options), with strict.
declare const anyValue: any;
declare const list: any[];
declare const anyTuple: [number, any];
declare const anyObject: { a: any; b: number; c: { d: any } };

const a1 = anyValue;
const a2: unknown = anyValue;
let a3: number;
a3 = anyValue;
const a4: Set<string> = new Set<any>();
const [a5] = list;
const [a6, a7] = anyTuple;
const { a: a8, b: a9 } = anyObject;
const { c: { d: a10 } } = anyObject;
const o1 = { key: anyValue };
const o2: { key: unknown } = { key: anyValue };
const o3: { key: Set<string> } = { key: new Set<any>() };
const arr = [...list];
const arr2 = [...anyValue];
const arr3 = [1, ...[2]];
class K {
  field = anyValue;
  field2: unknown = anyValue;
  field3: Set<string> = new Set<any>();
}
function def(p = anyValue) { return p; }
const m: Map<string, number> = new Map();
let a11: Set<string>;
a11 = new Set<any>();
let a12 = 1;
a12 += anyValue;
const [[a13]] = [[anyValue]] as [[any]];
const { 'x y': a14 } = { 'x y': anyValue } as { 'x y': any };
const a15 = missing;
void [a1, a2, a3, a4, a5, a6, a7, a8, a9, a10, o1, o2, o3, arr, arr2, arr3, K, def, m, a11, a12];
void [a13, a14, a15];

// Accessors, decorators, parameters and special keys.
declare function deco(...args: unknown[]): any;
const o4 = { get g() { return anyValue; }, set s(v: any) { void v; }, m() { return anyValue; } };
class K2 {
  @deco decorated = anyValue;
  accessor acc = anyValue;
  ['computed'] = anyValue;
  #privateOne = anyValue;
  get notChecked() { return anyValue; }
  constructor(private readonly pp = anyValue, @deco pd = anyValue) { void this.#privateOne; void pd; }
}
declare const odd: { __a: any; ___b: any; 16: any };
const { __a: r1, ___b: r2, 16: r3 } = odd;
const [, h1, , h2] = [1, anyValue, 2, anyValue] as [number, any, number, any];
const { q = anyValue } = {} as { q?: number };
const [w = anyValue] = [] as number[];
const o5 = { [`template`]: anyValue, 'chars': anyValue, 1: anyValue, k: (anyValue) };
let a16: number;
({ a: a16 } = anyObject);
for (const [x1] of [list]) { void x1; }
const a17: any = anyValue;
void [o4, K2, r1, r2, r3, h1, h2, q, w, o5, a16, a17];

// Destructuring keys: the name is String(value), with escapes, bases, exponents and BigInt.
declare const keys: { 'a\tb': any; 16: any; 1.5: any; 1e21: any; ABC: any; c: any; 1: any };
const { 'a\tb': k1, 0x10: k2, 1.50: k3, 1e21: k4, '\x41B\u{43}': k5, c: k6 } = keys;
const { [`a\tb`]: k7, [0b10000]: k8, 1n: k9 } = keys;
void [k1, k2, k3, k4, k5, k6, k7, k8, k9];

// `accessor` preceded by `static`/`override`, and as the name of a field.
class BaseAccessor { b: any; }
class WithAccessor extends BaseAccessor {
  static accessor a = anyValue;
  override accessor b = anyValue;
  static override accessor c = anyValue;
  accessor = anyValue;
}
void WithAccessor;
