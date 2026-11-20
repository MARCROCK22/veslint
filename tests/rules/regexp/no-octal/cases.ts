// Reported, with a suggestion.
export const a1 = /\07/;
export const a2 = /\1/;
export const a3 = /[\00]/;
export const a4 = /\077\377/;
export const a5 = new RegExp('é\\012');
export const a6 = /a\0012/;
// Not reported.
export const b1 = /\0/;
export const b2 = /[\7]/;
export const b3 = /[\1-\4]/;
export const b4 = /(a)\1/;
export const b5 = /\8/;
