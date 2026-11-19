// Reported.
export const a1 = /[A-\x43]/;
export const a2 = /[!-$]/;
export const a3 = /[ -~]/;
export const a4 = /[\0-\x1f]/;
export const a5 = new RegExp('[é-ü]');
export const a6 = /[a-\u{7a}]/u;
// Not reported.
export const b1 = /[a-z0-9A-Z]/;
export const b2 = /[\x00-\x40]/;
export const b3 = /[\cA-\cZ]/;
export const b4 = /[\1-\7]/;
export const b5 = /[a-a]/;
