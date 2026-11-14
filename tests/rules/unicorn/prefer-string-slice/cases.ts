// unicorn/prefer-string-slice: `slice()` instead of `substr()` and `substring()`; the arguments are
// rewritten where their values are known.
declare const text: string & { substr(a?: number, b?: number): string };
declare const n: number;

const s1 = text.substr();
const s2 = text.substr(1);
const s3 = text.substr(0, 3);
const s4 = text.substr(0, -3);
const s5 = text.substr(0, n);
const s6 = text.substr(0, text.length);
const s7 = text.substr(1, 2);
const s8 = text.substr(n, 2);
const s9 = text.substring();
const s10 = text.substring(2);
const s11 = text.substring(-2);
const s12 = text.substring(n);
const s13 = text.substring(text.length);
const s14 = text.substring(3, 1);
const s15 = text.substring(1, -1);
const s16 = text.substring(0, n);
const s17 = text.substring(n, 0);
const s18 = text.substring(n, n);
const s19 = text.substring(1, 2, 3);
const s20 = text.substring(...[1]);
const s21 = text?.substring(1);
const s22 = text.substring((n), 0);
const s23 = text.substr(0, -n);

// Not reported.
const z1 = text.slice(1);
const z2 = text['substring'](1);
