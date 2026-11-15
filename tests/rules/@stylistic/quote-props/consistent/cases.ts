export const a = { x: 1, 'y': 2, "z": 3 };
export const b = {
  'plain': 1,
  'two words': 2,
  ' lead': 3,
  'class': 4,
  'if': 5,
  'true': 6,
  'null': 7,
  '': 8,
  '1': 9,
  '1.0': 10,
  '1e+21': 11,
  '0x1': 12,
  '1e-7': 13,
  'Infinity': 14,
  'NaN': 15,
  'abc': 16,
  '\\u0061bc': 17,
  '\\u0069f': 18,
  '\\u{61}': 19,
  'ü': 20,
  '😀': 21,
  'a‍': 22,
  '1_0': 23,
  '01': 24,
  '.5': 25,
  '5.': 26,
  '0': 27,
  '-1': 28,
  'a/*x*/': 29,
  '100000000000000000000': 30,
  '1000000000000000000000': 31,
  '0.000001': 32,
  '1e-6': 33,
  'static': 34,
  'let': 35,
};
export const c = { 0x10: 1, 1e3: 2, 1n: 3, 1.50: 4, 0: 5 };
export const d = { method() { return 1; }, get g() { return 2; }, ['computed']: 3, a };
export const { x: renamed, 'y': other } = a;
export const e = { class: 1, if: 2, default: 3 };
interface I {
  a: string;
  'b': number;
  c(): void;
  'd'(): void;
  [key: string]: unknown;
}
type T = { 'only': string; 'quoted': number };
type U = { 'needed-quotes': string; plain: number };
enum E { A, 'B', C = 3 }
enum F { 'A', 'B' }
enum G { 'a-b', c }
export type { I, T, U };
export { E, F, G };
export const spread = { ...a, 'k': 1 };
