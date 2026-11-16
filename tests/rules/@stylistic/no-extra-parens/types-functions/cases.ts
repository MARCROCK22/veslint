// Type assertions and non-null assertions (precedence 2), in expressions.
declare let a: any, b: any, c: any, d: any;
declare function f<U = unknown>(...args: unknown[]): any;
f((a as any), (b satisfies unknown), (<any>c), (d!));
f(((a as any)));
a = (b as any);
a = (b!);
a = ((b as any));
export const n1 = (a!) + 1;
export const n2 = ((a as number)) + 1;
export const n3 = (a as number) * ((b as number));
export const n4 = ((a as any)) || b;
export const n5 = a + (b!);
export const m1 = ((a as any)).b;
export const m2 = (a!).b;
export const m3 = ((a!)).b;
export const m4 = (a as any)[(b as any)];
export const m5 = ((a satisfies any)).b;
export const m6 = (<any>a).b;
export const m7 = ((<any>a)).b;
export const m8 = (((a as any))).b;
export const c1 = ((a as any)) ? b : c;
export const c2 = a ? ((b as any)) : ((c as any));
export const c3 = (a!) ? (b!) : (c!);
export const c4 = (a as any) ? (b as any) : (c as any);
(a as any)();
((a as any))();
new (a as any)();
new ((a as any))();
(a!)();
((a!))();
typeof ((a as any));
typeof (a!);
void (a satisfies unknown);
export async function aw() { await ((a as any)); await (a!); }
(a as any)++;
((a as any))++;
(a!)++;
++((a as any));
export class X1 extends (a as any) {}
export class X2 extends ((a as any)) {}
export class X3 extends (a!) {}
export const arr = [(a as any), ((b!)), (c satisfies unknown)];
export const spread = [...(a as any), ...((b as any)), ...(c!)];
export const v1 = (a as any), v2 = ((a!)), v3 = (a satisfies any);
export const ternary = a ? b : (c!);
export const seq = ((a as any), (b!));
// An arrow body that starts with an object literal keeps its parentheses.
export const arrowObj = (w: string) => ({ a: 1 })[w] as number;
export const arrowObj2 = (w: string) => ({ a: 1 })[w] satisfies number;
export const arrowObj3 = (w: string) => ({ a: 1 })[w]!;
export const arrowObj4 = () => ({}).toString();
export const arrowObj5 = () => ({} as object);
export const arrowObj6 = () => (({}) as object);
export const arrowObj7 = () => ({}).x = b;
// Types.
type A = string;
type B = number;
type C = boolean;
type K = 'length';
interface T { length: number }
declare const x: string[];
type F1 = (() => string)[];
type F2 = (new () => string)[];
type F3 = (keyof T)[];
type F4 = (keyof T)[K];
type F5 = (A | B)[K];
type F6 = (() => void)[K];
type F7 = (typeof x)[number];
type F8 = (T)[K];
type F9 = ((A | B))[K];
type F10 = T[(K)];
type F11 = T[(K | 'length')];
type F12 = (readonly string[])[number];
type F13 = (string[])[number];
type F14 = ((string[]))[number];
type G1 = (A extends B ? 1 : 2) extends C ? A : B;
type G2 = A extends (B extends C ? 1 : 2) ? A : B;
type G3 = A extends B ? (A | B) : (C extends A ? 1 : 2);
type G4 = A extends B ? ((A)) : (C);
type G5<U> = U extends (infer V extends (string)) ? V : never;
type G6<U> = U extends [infer V extends (string)] ? V : never;
export function g1<U extends (A | B) = (A | B)>(u: U) { return u; }
export function g2<U extends (A), V = ((B))>(u: U, v: V) { return [u, v]; }
type M1 = Map<(A), (B | C)>;
type M2 = Array<((A))>;
type M3 = Array<(() => void)>;
f<(A)>(1);
f<(A) | B>(1);
export const map = new Map<(A), B>();
type U1 = (A) | (B);
type U2 = (A[]) | B;
type U3 = (keyof T) | B;
type U4 = (() => void) | B;
type U5 = (typeof x) | B;
type U6 = (T[K]) | B;
type I1 = (keyof T) & B;
type I2 = (typeof x) & B;
type I3 = (A) & (B);
type R1 = (readonly string[])[];
type R2 = (keyof T)[];
type Mapped = { [P in (keyof T)]: (T[P]) };
type Fn = (a: (A)) => (B);
export type { F1, F2, F3, F4, F5, F6, F7, F8, F9, F10, F11, F12, F13, F14, G1, G2, G3, G4, G5, G6, M1, M2, M3 };
export type { U1, U2, U3, U4, U5, U6, I1, I2, I3, R1, R2, Mapped, Fn };
