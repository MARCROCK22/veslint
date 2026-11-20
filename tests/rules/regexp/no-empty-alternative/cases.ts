// Reported, with a suggestion when the empty alternative is the first or the last.
export const a1 = /a|/;
export const a2 = /|a/;
export const a3 = /a||b/;
export const a4 = /(a|)/;
export const a5 = /(?<n>|a|b)/;
export const a6 = /(?:a|)+/;
export const a7 = /x(?:|b|c)*y/u;
export const a8 = /[\q{a|}]/v;
export const a9 = new RegExp('é(a|)');
export const a10 = new RegExp('a' + '|');
// Not reported.
export const b1 = /a|b/;
export const b2 = /()|a/;
export const b3 = /(?:)/;
export const b4 = /[\q{}]/v;
