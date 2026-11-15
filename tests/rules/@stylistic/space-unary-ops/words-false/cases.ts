declare let a: number, x: number, o: { a?: number; b: number[] }, n: number | null, s: string;
declare class Foo { constructor(v?: number) }

export const w1 = typeof x, w2 = typeof(x), w3 = typeof  x, w4 = typeof /* c */x, w5 = typeof'a';
export const w6 = void 0, w7 = void(0), w8 = typeof-x, w9 = typeof+x, w10 = typeof!x;
delete o.a;
delete(o.a);
export const n1 = new Foo, n2 = new(Foo), n3 = new  Foo(), n4 = new Foo(1), n5 = new /* c */ Foo;
export const u1 = -x, u2 = - x, u3 = +x, u4 = + x, u5 = !x, u6 = ! x, u7 = !!x, u8 = ! !x, u9 = ~x, u10 = ~ x;
export const u11 = -(-x), u12 = - -x, u13 = + +x, u14 = - +x, u15 = -!x, u16 = !-x, u17 = -'a', u18 = - /* c */ x;
++a;
++ a;
a++;
a ++;
a --;
-- a;
a/* c */++;
o.b[0]++;
o.b[0] ++;
export function* gen(): Generator<number, void, number> {
  yield x;
  yield(x);
  yield  x;
  yield* [x];
  yield *[x];
  yield;
  const v = yield;
  yield -x;
  yield/* c */x;
  return v;
}
export async function asy(): Promise<number> {
  await x;
  await(x);
  await  x;
  await /* c */ x;
  await -x;
  return (await x) + await(x);
}
export const nn1 = n!, nn2 = n !, nn3 = (n)!, nn4 = n!!, nn5 = o.b[0]!, nn6 = o.a!.toFixed(), nn7 = o.a ! .toFixed();
export const nn8 = (n /* c */ )!, nn9 = s! + s;
export const mix = typeof void delete o.a, mix2 = - - - x, mix3 = !!!x;
