// @ts-check
// @ts-expect-error: TS1234 because of a reason
let a = 1;
// @ts-expect-error: TS1234 because
let b = 2;
// @ts-expect-error: x
let c = 3;
// @ts-expect-error
let d = 4;
// @ts-ignore a/b
let e = 5;
// @ts-ignore ab
let f = 6;
/* @ts-expect-error:  TS1 because x */
let g = a + b + c + d + e + f;
export { g };
