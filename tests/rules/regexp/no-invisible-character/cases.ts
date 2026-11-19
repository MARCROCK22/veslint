// Reported: invisible characters written as themselves, with a fix.
export const a1 = /a b/;
export const a2 = /[	]/;
export const a3 = /x​y/u;
export const a4 = new RegExp("　é ");
export const a5 = new RegExp('a b	 c');
export const a6 = /⠀/;
// Not reported: the space, escapes, and the characters of a template or a concatenation.
export const b1 = / /;
export const b2 = /\u00a0\t/;
export const b3 = new RegExp(` `);
export const b4 = new RegExp("a" + " ");
