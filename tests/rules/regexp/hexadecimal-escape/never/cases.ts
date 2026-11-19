// Reported ("never"): hexadecimal escapes, with a fix.
export const a1 = /\x0a/;
export const a2 = /[\xFf]/;
export const a3 = new RegExp('é\\x41');
// Not reported.
export const b1 = /\u000a/;
export const b2 = /\u{a}/u;
