type Data = { name: string; num: number };
type NullableData = null | Data;
// Reported.
type A = Omit<Data, 'name' | 'num'>;
type B = Pick<Data, never>;
type C = Omit<NullableData, 'name'>;
type D = Partial<Omit<Data, keyof Data>>;
type E = Omit<Data, 'name' | 'num'> & Omit<Data, keyof Data>;
type F = Readonly<Record<never, string>> | string;
type G = Map<string, Omit<Data, keyof Data>>;
declare const h: Omit<NullableData, 'num'>;
function i(x: Omit<Data, keyof Data>): void {}
type J = NonNullable<unknown>;
interface K extends Omit<Data, 'name' | 'num'> {}
type L = Exclude<{} | string, string>;
type M = Required<{}>;
// Not reported.
type N = {};
type O = Omit<Data, 'name'>;
type P = Record<string, never>;
type Q = Array<string>;
type R = Data & { other: string };
type S = Omit<Data, 'name'> & {};
type T = Promise<void>;
type U = Exclude<() => void, undefined>;
interface V {}
type W = Readonly<V>;
class X {}
type Y = Partial<X>;
type Z<T> = Omit<T, keyof T>;
type AA = Uppercase<'a'>;
type AB = typeof import('./cases');
