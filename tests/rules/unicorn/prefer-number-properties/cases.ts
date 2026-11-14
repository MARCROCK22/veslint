// unicorn/prefer-number-properties: `Number.parseInt` and the others instead of the globals.
// `isNaN` and `isFinite` get a suggestion (they convert their argument), a fix when the argument
// is a number; `parseInt` with no radix or radix 10 is not reported; `Infinity` is checked with
// checkInfinity (infinity/) and `NaN` with checkNaN (nan/).
const a1 = parseInt('10', 10);
const a2 = parseFloat('1.5');
const a3 = isNaN(1);
const a4 = isFinite(1);
const a5 = NaN;
const a6 = Infinity;
const a7 = -Infinity;
const a8 = globalThis.parseInt('1');
const a9 = { NaN };
function f() {
  return-Infinity;
}
const parse = parseInt;

// Not reported.
const z1 = Number.parseInt('1');
function shadowed(parseInt: (s: string) => number) {
  return parseInt('1');
}

// parseInt with another radix, an unknown one or a spread one.
const b1 = parseInt('10', 16);
declare const radix: number;
const b2 = parseInt('10', radix);
declare const args: [string, number];
const b3 = parseInt(...args);
const ten = 10;
const b4 = parseInt('10', ten);
const b5 = parseInt('10', 5 + 5);

// isNaN and isFinite of a number: fixed.
function numbers(n: number, s: string, list: string[], map: Map<string, number>, date: Date) {
  isNaN(n);
  isFinite(n!);
  isNaN(s.length);
  isFinite(s.indexOf('x'));
  isNaN(list.length);
  isNaN(list.push('a'));
  isFinite(list.findIndex(Boolean));
  isNaN(map.size);
  isFinite(date.getTime());
  isNaN(Math.f16round(1.5));
  isNaN(Date.now());
  isFinite(n + 1);
  isNaN(s as unknown as number);
  isNaN(n ? 1 : 2);
  isFinite(`${n}`.charCodeAt(0));
  isNaN((() => 1).length);
  isNaN(new Set([1]).size);
  isNaN(s.trim().lastIndexOf('a'));
  isFinite(/a/.source.length);
}
declare const typed: 1 | 2;
isNaN(typed);
declare const inferred: ReturnType<typeof Math.random>;
isFinite(inferred);

// isNaN and isFinite of something else: suggested.
function others(s: string, u: unknown, b: bigint, o: { length: string }, w: WeakMap<object, number>) {
  isNaN(s);
  isFinite(u);
  isNaN(b);
  isNaN(o.length);
  isFinite(w as unknown as number | string);
  isNaN(s, s);
  isNaN(...[s]);
  isFinite(s.search('a'));
}
