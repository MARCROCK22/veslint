// Reported, with a fix.
export const a1 = /(?:a?)+/;
export const a2 = /(?:a{2})*/;
export const a3 = /(?:a+?)*?/;
export const a4 = /(?:a|b?)+/;
export const a5 = /(?:a{2,3}|b*)+/;
export const a6 = /(?:a{1,4}|b)*/;
export const a7 = new RegExp('é(?:\\d*)?');
// Not reported.
export const b1 = /(?:a{2}){3,4}/;
export const b2 = /(?:a+)+?/;
export const b3 = /(a+)+/;
export const b4 = /(?:a{0})+/;
export const b5 = /(?:a{2,3}){2,3}/;
