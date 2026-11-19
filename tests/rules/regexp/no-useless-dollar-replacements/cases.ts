// Reported: references to capturing groups the pattern does not have.
declare const text: string;
export const a1 = text.replace(/(a)/, '$2');
export const a2 = text.replace(/a/, '$1');
export const a3 = text.replaceAll(/(?<x>a)/g, '$<y>');
export const a4 = text.replace(/a/, '$<y>');
export const a5 = text.replace(/(a)(b)/, 'é$03 $3');
const re = /(c)/;
export const a6 = text.replace(re, "$2$$1");
// Not reported.
export const b1 = text.replace(/(a)/, '$1');
export const b2 = text.replace(/(?<x>a)/, '$<x>$&');
export const b3 = text.replace(/a/, '$$1');
declare const other: { replace(a: RegExp, b: string): void };
other.replace(/a/, '$1');
export const b4 = text.replace(/a/, `$1`);
