// Reported ("always"): unicode escapes of characters up to U+00FF, with a fix.
export const a1 = /\u000a/;
export const a2 = /\u{a}/u;
export const a3 = /[ÿ]/;
export const a4 = new RegExp('é\\u0041');
// Not reported.
export const b1 = /\x0a/;
export const b2 = /Ā/;
export const b3 = /\cA\0/;
