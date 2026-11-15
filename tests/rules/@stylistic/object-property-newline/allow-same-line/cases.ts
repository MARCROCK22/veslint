// Each property on its own line.
export const a = { x: 1, y: 2 };
export const b = {
  x: 1, y: 2,
  z: 3,
};
export const c = {
  x: 1,
  y: 2,
};
export const d = { x: 1, /* comment */ y: 2 };
export const e = { x: 1,	y: 2,  z: 3 };
export const f = { ...a, ...b };
export const g = { [`k${1}`]: 1, m() { return 1; }, get n() { return 2; } };
type T = { a: string; b: number };
type U = {
  a: string; b: number;
};
interface I { a: string; b(): void }
interface J {
  a: string, b: number
}
export type { T, U, I, J };
export const h = { x: 1,
  y: 2, z: 3 };
export const single = { x: 1 };
export const multiline = { x: {
  inner: 1 }, y: 2 };
