const a = 1, b = 1;
type X = 1;
type Y = 1;
export { a, b };
export { b as b2, a as a2 };
export type { X, Y };
export type { Y as Z, X as W };
