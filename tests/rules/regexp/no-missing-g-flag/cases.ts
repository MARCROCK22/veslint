// Reported: matchAll and replaceAll of a string with a regular expression without `g`.
declare const text: string;
export const a1 = text.replaceAll(/foo/, 'bar');
export const a2 = text.matchAll(/foo/i);
export const a3 = 'abc'.matchAll(new RegExp('b'));
export const a4 = text.replaceAll(new RegExp('é', 'u'), '');
const re = /x/;
export const a5 = text.matchAll(re);
const flags = 'i';
export const a6 = text.matchAll(new RegExp('y', flags));
export const a7 = `${text}`.replaceAll(RegExp('z'), 'w');
export function f(s: string | 'lit'): void {
  s.replaceAll(/[\q{a}]/v, '');
}
// Not reported.
export const b1 = text.replaceAll(/foo/g, 'bar');
export const b2 = text.replace(/foo/, 'bar');
declare const notString: { matchAll(r: RegExp): void };
notString.matchAll(/foo/);
declare const flagsUnknown: string;
export const b3 = text.matchAll(new RegExp('y', flagsUnknown));
export const b4 = (text as any).matchAll(/foo/);
