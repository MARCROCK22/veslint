const x = 1;
// Reported.
enum A {
  a = x,
  b = 1 + 1,
  c = `t${x}`,
  d = -x,
  e = 1 << 0,
  f = ~1,
  g = 'a'.length,
  h = a,
  i = A.a,
  'ü' = (1),
  k = 1 as number,
}
// Not reported.
enum B {
  a = 1,
  b = 'b',
  c = `c`,
  d = -1,
  e = +2,
  f = -(-3),
  g = 0x10,
  h,
  i = null as any,
  j = /re/ as any,
  k = 1n as any,
  l = true as any,
}
declare enum C {
  a = 1,
  b = x,
}
