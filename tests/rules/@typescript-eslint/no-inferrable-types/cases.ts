// Variables.
const a1: bigint = 10n;
const a2: bigint = -10n;
const a3: bigint = BigInt(10);
const a4: bigint = -BigInt?.(10);
const a5: bigint = 'any literal';
const a6: bigint = (10n);
const b1: boolean = false;
const b2: boolean = !0;
const b3: boolean = Boolean(null);
const b4: boolean = !!b1;
const n1: number = 10;
const n2: number = +10;
const n3: number = -(10);
const n4: number = Infinity;
const n5: number = -NaN;
const n6: number = Number('1');
const n7: number = +Number?.('1');
const n8: number = 0x10;
const u1: null = null;
const s1: string = 'str';
const s2: string = `template`;
const s3: string = `with ${n1} substitution`;
const s4: string = String(1);
const y1: symbol = Symbol('a');
const r1: RegExp = /a/u;
const r2: RegExp = new RegExp('a');
const r3: RegExp = RegExp('a');
const r4: RegExp = new (RegExp)('a');
const v1: undefined = void 0;
const v2: undefined = undefined;
let spaced : number = 1;
let commented: /* type */ number /* after */ = 1;
let parenthesized: (number) = 1;
let multi: number = 1, other: string = '', untyped = 3;
for (let i: number = 0; i < 1; i++) {}
declare const ambient: number;
let ascii: number = 1;
// Not inferrable.
const x1: number = n1;
const x2: number = -(-1);
const x3: boolean = true as boolean;
const x4: string = String;
const x5: string = tag`x`;
const x6: symbol = Symbol;
const x7: RegExp = new RegExp2('a');
const x8: Foo.RegExp = /a/;
const x9: unique symbol = Symbol();
const x10: number = 10n;
const x11: undefined = null;
const x12: null = undefined;
const x13: object = {};
const x14: number | string = 1;
const x15: bigint = BigInt.asIntN(1, 1n);
const x16: number = new Number(1);
const x17: any = 1;
declare function tag(s: TemplateStringsArray): string;
declare function RegExp2(s: string): RegExp;
declare namespace Foo { type RegExp = globalThis.RegExp; }

// Parameters.
function f1(a: number = 5, b?: boolean = true, c: string = '') {}
const f2 = function (a: bigint = 1n) {};
const f3 = (a: RegExp = /x/, b = 1, ...rest: number[]) => a;
function* f4(a: null = null) {}
async function f5(a: undefined = undefined) {}
class C1 {
  constructor(private a: number = 5, readonly b?: string = '', @dec c: boolean = true, public d = 1, protected override e: number = 1) {}
  method(a: number = 1, { b }: { b: number } = { b: 1 }) {}
  get g() { return 1; }
  set s(v: number = 1) {}
  static m(@dec a: symbol = Symbol()) {}
}
const obj = {
  m(a: number = 1) {},
  async *g(a: string = '') {},
  arrow: (a: boolean = false) => a,
};
declare function d1(a: number = 1): void;
function overload(a: number = 1): void;
function overload(a: number = 1) {}
declare class C2 { m(a: number = 1): void; }
type T1 = (a: number = 1) => void;
interface I1 { m(a: number = 1): void; }
declare function dec(...args: unknown[]): any;

// Properties.
class C3 {
  a: number = 5;
  b?: number = 5;
  c!: number = 5;
  readonly d: number = 5;
  static e: string = '';
  private f: boolean = true;
  @dec g: number = 1;
  declare h: number;
  accessor i: number = 1;
  accessor j!: number = 1;
  static accessor k: string = '';
  #l: number = 1;
  ['m']: number = 1;
  override n: number = 1;
  o: number = n1;
  p = 1;
}
abstract class C4 {
  abstract a: number;
  c: number = 1;
}
const objProps = { a: 1 as number };
export {};
