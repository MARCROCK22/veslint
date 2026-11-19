// Reported (uppercase letters and escapes, lowercase control escapes).
export const a1 = /a/i;
export const a2 = /[b-z]/i;
export const a3 = /\u000a/;
export const a4 = /\x0b/;
export const a5 = /\cA/;
export const a6 = /[\q{ab}]/iv;
// Not reported.
export const b1 = /A/i;
export const b2 = /\u000A\x0B\ca/;
