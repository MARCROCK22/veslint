// Reported (defaults: lowercase letters with `i`, lowercase escapes, uppercase control escapes).
export const a1 = /A/i;
export const a2 = /[B-Z]/i;
export const a3 = /\u000A/;
export const a4 = /\u{A}/u;
export const a5 = /\x0A/;
export const a6 = /\ca/;
export const a7 = /J/i;
export const a8 = new RegExp('é\\x0B', 'i');
// Not reported.
export const b1 = /A/;
export const b2 = /[a-Z]/i;
export const b3 = /[A-z]/i;
export const b4 = /\u000a\x0b\cA/;
export const b5 = /[\q{AB}]/v;
