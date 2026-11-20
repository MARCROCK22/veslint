// Reported.
export const a1 = /\c/;
export const a2 = /[\c]/;
export const a3 = /\c-/;
export const a4 = new RegExp('é\\c1');
// Not reported.
export const b1 = /\\/;
export const b2 = /\cA/;
export const b3 = /[\c_]/;
