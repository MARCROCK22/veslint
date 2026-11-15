// @ts-nocheck abc
// @ts-check abcdef
// @ts-check  a
// @ts-ignore
let a = 1;
// @ts-ignore 123456
let b = 2;
// @ts-expect-error with a long description
let c = a + b;
export { c };
