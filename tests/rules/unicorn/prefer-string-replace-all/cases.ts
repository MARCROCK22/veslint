// unicorn/prefer-string-replace-all: `replaceAll()` instead of `replace()` with a global regular
// expression, and a string instead of a pattern of plain characters.
declare const text: string;
declare const pattern: RegExp;

const r1 = text.replace(/a/g, 'b');
const r2 = text.replace(/abc/gu, 'b');
const r3 = text.replace(/a\.b/g, '');
const r4 = text.replace(/'/g, '"');
const r5 = text.replace(/\\/g, '/');
const r6 = text.replace(/\n\t\cJ\cA/g, ' ');
const r7 = text.replace(/a+/g, '');
const r8 = text.replace(new RegExp('a', 'g'), '');
const r9 = text.replaceAll(/a/g, '');
const r10 = text.replaceAll(/a very long pattern here/g, '');
const global = /x/g;
const r11 = text.replace(global, '');
const r12 = text?.replace(/a/g, '');
const r13 = text.replace(/\x41B/g, '');

// Not reported.
const z1 = text.replace(/a/, 'b');
const z2 = text.replace(/a/gi, 'b');
const z3 = text.replaceAll(/a|b/g, '');
const z4 = text.replace(pattern, '');
const z5 = text.replace('a', 'b');
const z6 = text.replace?.(/a/g, 'b');
const z7 = text.replace(/a/g);
