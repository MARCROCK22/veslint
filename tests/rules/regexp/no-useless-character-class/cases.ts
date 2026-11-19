// Reported, with a fix.
export const a1 = /[a]/;
export const a2 = /[\d]/;
export const a3 = /[.]/;
export const a4 = /[a-a]/;
export const a5 = /[$]x/;
export const a6 = /[}]/u;
export const a7 = /[[a]]/v;
export const a8 = /[[ab]c]/v;
export const a9 = /[[]^a]/v;
export const a10 = /[a&&[b]]/v;
export const a11 = /[[\q{abc}]]/v;
export const a12 = new RegExp('é[\\w]');
// Not reported.
export const b1 = /[=]/;
export const b2 = /[^a]/;
export const b3 = /[\b]/;
export const b4 = /[ab]/;
export const b5 = /[\1]/;
export const b6 = /\c[a]/;
export const b7 = /[\q{abc}]/v;
