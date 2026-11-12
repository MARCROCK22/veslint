/** doc a */
declare function f(a: string): void;
/** doc b */
declare function f(a: number): void;
/** same */
declare function g(a: string): void;
/** same */
declare function g(a: number): void;
declare function h(a: string): void;
declare function h(a: number): void;
// line comment
/** block */ // line after
declare function i(a: string): void;
/** block */
declare function i(a: number): void;
/* plain block */
export function j(a: string): void;
/* plain block */
export function j(a: number): void;
export function j(a: unknown) {}
/** declared */
export declare function k(a: string): void;
/** declared */
export declare function k(a: number): void;
/** a */ /** b */
declare function l(a: string): void;
/** b */
declare function l(a: number): void;
/** only one */
declare function m(a: string): void;
declare function m(a: number): void;
class K {
  /** one */
  m(a: string): void;
  /** two */
  m(a: number): void;
  m(a: unknown) {}
  /** same */
  public static n(a: string): void;
  /** same */
  public static n(a: number): void;
  static n(a: unknown) {}
}
interface L {
  /** x */ (a: string): void;
  /** x */ (a: number): void;
  /** y */ m(): void;
  /** z */ m(a: string): void;
}
export {};
