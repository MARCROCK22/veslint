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
