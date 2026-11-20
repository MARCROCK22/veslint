// Reported.
export const a1 = /[\q{}]/v;
export const a2 = /[\q{|}]/v;
export const a3 = /[a\q{||}b]/v;
export const a4 = new RegExp('[\\q{}]', 'v');
// Not reported.
export const b1 = /[\q{a}]/v;
export const b2 = /[\q{a|}]/v;
export const b3 = /\q{}/;
