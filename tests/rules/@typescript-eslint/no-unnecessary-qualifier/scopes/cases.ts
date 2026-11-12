// Cases of no-unnecessary-qualifier where what checker.getSymbolsInScope gives and what
// checker.resolveName finds could differ: the rule looks the name up among the symbols in scope
// whose flags share a bit with those of the accessed one.
namespace Other { export const y = 2; export type Y = string; export function g(): void {} }

// An import alias has no flag in common with what it names: it does not hide the member.
namespace WithAlias {
  export const x = 1;
  export type T = string;
  export function f(): void {}
  namespace Inner {
    import x = Other.y;
    import T = Other.Y;
    import f = Other.g;
    export const a = WithAlias.x + x;
    export const b: WithAlias.T | T = '';
    export const c = [WithAlias.f, f];
  }
  void Inner;
}
namespace WithAlias {
  import x = Other.y;
  export const again = WithAlias.x + x;
}
namespace ExportedAlias {
  export import x = Other.y;
  export const a = ExportedAlias.x;
  namespace Inner {
    export const b = ExportedAlias.x;
  }
  void Inner;
}

// The locals of a function are in scope in its parameters, return type and decorators too.
declare function decorate(...args: unknown[]): any;
namespace InFunctions {
  export const x = 1;
  export type T = string;
  export const dec = decorate;
  export function initializer(a = InFunctions.x): number { const x = 2; return a + x; }
  export function initializerVar(a = InFunctions.x): number { var x = 2; return a + x; }
  export function initializerSafe(a = InFunctions.x): number { const y = 2; return a + y; }
  export function initializerNested(a = InFunctions.x): number { { const x = 2; return a + x; } }
  export function parameterType(a: InFunctions.T): unknown { type T = number; return a as unknown as T; }
  export function returnType(): InFunctions.T { type T = number; return '' as unknown as T as never; }
  export function typeParameter<T>(a: InFunctions.T, b: T): unknown { return [a, b]; }
  export function parameterNamed(x: number, b = InFunctions.x): number { return x + b; }
  export const arrow = (a = InFunctions.x): number => { const x = 2; return a + x; };
  export const expression = function x(a = InFunctions.x): number { return a; };
  export class Decorated {
    @InFunctions.dec method(): number { const dec = 1; return dec; }
    @InFunctions.dec other(): number { return 1; }
    withParameter(@InFunctions.dec a: number): number { const dec = 1; return a + dec; }
    field = InFunctions.x;
    static x = InFunctions.x;
    x = InFunctions.x;
  }
  export function nested(): number {
    const x = 2;
    return ((a = InFunctions.x) => a + x)();
  }
}

// `arguments` is not a variable for getSymbolsInScope.
namespace WithArguments {
  export const args = 1;
  export function f(): unknown { return [WithArguments.args, arguments]; }
}

// A type and a value with the same name, merged declarations and reopened namespaces.
namespace Meanings {
  export const both = 1;
  export type both = string;
  export interface Merged { a: number }
  export function Merged(): void {}
  export namespace Merged { export const inner = 1; }
  export enum Color { Red, Green = Color.Red, Blue = Red }
  export const enum Constant { A = 1, B = Constant.A }
  namespace Inner {
    const both = 2;
    type Shadow = Meanings.both;
    export const a: Shadow = String(Meanings.both + both);
    export const b: Meanings.Merged = { a: 1 };
    export const c = Meanings.Merged;
    export const d = Meanings.Merged.inner;
    export const e = Meanings.Color.Red;
    export type both = number;
    export const f = Meanings.both;
  }
  void Inner;
  export function shadowed(both: number): unknown { return [both, Meanings.both, null as unknown as Meanings.both]; }
  export function typeShadowed<both>(a: both): unknown { return [a, Meanings.both, null as unknown as Meanings.both]; }
  export class Class<Merged> { m(a: Merged): unknown { return [a, Meanings.Merged, null as unknown as Meanings.Merged]; } }
}
namespace Reopened {
  export const local = Reopened.fromOther + Reopened.shared;
  export const typed: Reopened.OtherType = '';
  namespace Inner {
    const shared = 3;
    export const a = Reopened.shared + shared + Reopened.fromOther;
  }
  void Inner;
}
enum ReopenedEnum { Second = ReopenedEnum.First, Third = First }

// Members of enums against other symbols with their name.
const First = 0;
enum Outer { First, Second = Outer.First }
namespace EnumHolder {
  export enum Kind { A, B }
  export const A = 1;
  export const kinds = [EnumHolder.Kind.A, EnumHolder.A, EnumHolder.Kind];
  export enum Kind { C = EnumHolder.Kind.A, D = Kind.B, E = EnumHolder.A }
}
void [First, Outer, WithAlias, ExportedAlias, InFunctions, WithArguments, Meanings, Reopened, EnumHolder];
