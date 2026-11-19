// Reported: the legacy static properties of RegExp, and RegExp#compile.
export const a1 = RegExp.$1;
export const a2 = RegExp.input;
export const a3 = RegExp['$&'];
export const a4 = globalThis.RegExp.lastMatch;
const { leftContext } = RegExp;
export { leftContext };
const re = /a/;
re.compile('b');
export const a5 = new RegExp('a').compile;
// Not reported.
export const b1 = RegExp.prototype;
declare const other: { compile(): void };
other.compile();
export function local(RegExp: { $1: string }): string {
  return RegExp.$1;
}
