// Reported, with a fix.
export const a1 = /\x00/;
export const a2 = /\x0a/;
export const a3 = /\u000d/u;
export const a4 = /\cJ/;
export const a5 = /[\x09]/;
export const a6 = /\u{b}/u;
export const a7 = new RegExp('\\x0c');
export const a8 = new RegExp("é\\cI");
export const a9 = /	/;
// Not reported: the escapes themselves, ranges, and the characters themselves in a string.
export const b1 = /\0\t\n\v\f\r/;
export const b2 = /[\x00-\x0d]/;
export const b3 = new RegExp('\t\n');
export const b4 = new RegExp(`\n`);
export const b5 = /\x0e/;
