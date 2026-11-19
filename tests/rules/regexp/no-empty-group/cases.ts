// Reported: empty groups in literals.
export const a1 = /()/;
export const a2 = /(?:)/u;
export const a3 = /a(|)b/v;
export const a4 = /(?<name>)/;
export const a5 = /x(?:(?:))/;
// Not reported.
export const b1 = /(a)/;
export const b2 = /(a|)/;
export const b3 = /(?:a|[\q{}])/v;

// RegExp calls: strings, escapes and non-ASCII text before the group.
export const c1 = new RegExp('()');
export const c2 = RegExp("é\\d(?:)");
export const c3 = new RegExp('😀(|)', 'u');
export const c4 = new RegExp(`a()`);
export const c5 = globalThis.RegExp('(?:|)');
const source = 'b()';
export const c6 = new RegExp(source);
export const c7 = new RegExp('a' + '()' + 'b');
const part = '(?:)';
export const c8 = new RegExp('x' + part, 'g');
export const c9 = new RegExp(/()/.source);
export const c10 = new RegExp(/(?:)/, 'i');
const shared = /(|)/g;
export const c11 = new RegExp(shared);
export const c12 = shared.test('x');

// Unknown or invalid patterns, and a RegExp that is not the global one.
declare const unknown: string;
export const d1 = new RegExp(unknown + '()');
export const d2 = new RegExp('(');
export function local(RegExp: (s: string) => RegExp): RegExp {
  return RegExp('()');
}
export const d3 = new RegExp('a\
()');
