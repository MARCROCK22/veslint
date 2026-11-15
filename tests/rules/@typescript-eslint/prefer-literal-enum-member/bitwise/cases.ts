const x = 1;
// Not reported.
enum A {
  a = 1 << 0,
  b = 1 << 1,
  c = a | b,
  d = A.a | A['b'],
  e = ~a,
  f = ~(a & b),
  g = -a | 1,
  h = 'x'.length >>> 0 as any,
  'ü' = 4,
  i = ü ^ a,
  j = A[`ü`] >> 1,
  k = 1 >>> 0,
}
// Reported.
enum B {
  a = 1,
  b = a,
  c = a + 1,
  d = x | 1,
  e = !a,
  f = B[x] | 1,
  g = A.a | 1,
  h = Other.a | 1,
  i = B[''] | 1,
}
declare const Other: { a: number };
