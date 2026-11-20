// Reported: the first non-standard flag.
export const a1 = RegExp('foo', 'gl');
export const a2 = new RegExp('(', 'xl');
declare const unknown: string;
export const a3 = new RegExp(unknown, 'gq');
const flags = 'zi';
export const a4 = new RegExp('a', flags);
export const a5 = new RegExp('a', `g${'w'}`);
// Not reported.
export const b1 = /foo/dgimsy;
export const b2 = new RegExp('a', 'v');
export const b3 = new RegExp('a', unknown);
export const b4 = new RegExp(/a/);
