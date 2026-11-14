// Reported, with suggestions.
const a: any = 1;
function f1(x: any): any { return x; }
function f2(...args: any[]): void { f2(...args); }
function f3(...args: any): void { f3(...args); }
function f4(...args: readonly any[]): void { f4(...args); }
function f5(...args: Array<any>): void { f5(...args); }
function f6(...args: ReadonlyArray<any>): void { f6(...args); }
type K = keyof any;
type L = Record<string, any>;
type M = Promise<any>[];
type N = { [k: string]: any };
type O = (...args: any[]) => any;
type P = new (...args: any[]) => unknown;
interface Q { m(...args: any[]): void; (...args: any[]): void; new (...args: any[]): Q }
declare function d(...args: any[]): void;
declare class R { m(...args: any[]): void; }
const g = (...args: any[]) => args;
const h = function (...args: any[]) { return args; };
const i = <T = any>(x: T) => x;
class S<T extends any> { p: any; constructor(public q: any) {} }
let j = a as any;
let k = <any>a;
type T1 = any | string;
type T2 = { a: any }['a'];
function f7({ x }: { x: any }) { return x; }
function f8(...[x]: any[]) { return x; }

// Not reported.
const u: unknown = 1;
type V = keyof unknown;
export { a, f1, f2, f3, f4, f5, f6, d, R, g, h, i, S, j, k, f7, f8, u };
export type { K, L, M, N, O, P, Q, T1, T2, V };
