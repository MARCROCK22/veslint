// Reported, with a suggestion.
export const a1 = /[\b]/;
export const a2 = /[a\bc]/u;
export const a3 = new RegExp('[\\b]');
export const a4 = new RegExp("é[\\b-z]");
// Not reported.
export const b1 = /\b/;
export const b2 = /[\u0008]/;
export const b3 = /\x08/;
