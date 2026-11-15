#!/usr/bin/env node @ts-ignore in the shebang
// @ts-ignore
let a = 1;
// @ts-ignore: with a description, still reported
let b = 2;
/* @ts-ignore */
let c = 3;
/**
 * a doc
 * @ts-ignore twice @ts-ignore
 */
let d = 4;
/** @ts-ignore */
let e = 5;
///@ts-ignore
let f = 6;
//    @ts-ignore    spaces
let g = 7;
// @ts-expect-error
let h = 8;
// @ts-expect-error: ab
let i = 9;
// @ts-expect-error:   abc   
let j = 10;
// @ts-expect-error 👨‍👩‍👧‍👦👨‍👩‍👧‍👦
let k = 11;
// @ts-expect-error 👨‍👩‍👧‍👦👨‍👩‍👧‍👦👨‍👩‍👧‍👦
let l = 12;
// @ts-expect-error: é́́
let m = 13;
/* @ts-expect-error */
let n = 14;
/*
 @ts-expect-error
 */
let o = 15;
/*
 * @ts-expect-error the description is enough */
let p = 16;
// @ts-check
// @ts-nocheck after the first statement
/// @ts-nocheck
// not a @ts-ignore directive
// @ts-ignored
// @ts-expect-errors
let q: number = a + b + c + d + e + f + g + h + i + j + k + l + m + n + o + p;
function x() {
  // @ts-ignore inside a function
  return q;
}
x();
