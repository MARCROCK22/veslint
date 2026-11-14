// unicorn/prefer-code-point: codePointAt() and fromCodePoint() handle astral characters.
declare const text: string;

const c1 = text.charCodeAt(0);
const c2 = text?.charCodeAt(0);
const c3 = String.fromCharCode(65);
const c4 = String.fromCharCode;

// Not reported.
const z1 = text.charCodeAt?.(0);
const z2 = String?.fromCharCode(65);
const z3 = text.codePointAt(0);
const z4 = text['charCodeAt'](0);

// 79.0.0: no suggestion when the result is used as a number.
let hash = 0;
hash = (hash << 5) - hash + text.charCodeAt(0);
hash += text.charCodeAt(1);
hash ||= text.charCodeAt(2);
const n1 = -text.charCodeAt(3);
const n2 = (text.charCodeAt(4) as number) | 0;
const n3 = (true ? text.charCodeAt(5) : 0) * 2;
const n4 = text?.charCodeAt(6) ?? 0 + 1;
const n5 = !text.charCodeAt(7);
