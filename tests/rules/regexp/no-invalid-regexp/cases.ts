// Reported: invalid patterns of RegExp calls, at the error index.
export const a1 = new RegExp('(');
export const a2 = RegExp('[', 'u');
export const a3 = new RegExp('é\\k<x>', 'u');
export const a4 = new RegExp('a' + '{2,1}');
const pattern = 'x(?<n>a)(?<n>b)';
export const a5 = new RegExp(pattern);
export const a6 = new RegExp(`\\p{Nope}`, 'u');
export const a7 = new RegExp('😀)');
export const a8 = new RegExp('\\');
// Unknown patterns: duplicate flags, or both u and v.
declare const unknown: string;
export const b1 = new RegExp(unknown, 'gg');
export const b2 = new RegExp(unknown, 'uv');
export const b3 = new RegExp(unknown, 'ggi');
const flags = 'iuv';
export const b4 = new RegExp(unknown, flags);
// Not reported.
export const c1 = new RegExp('(a)');
export const c2 = new RegExp(unknown, 'gu');
export const c3 = /valid/u;
export const c4 = new RegExp(unknown);
