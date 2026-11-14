declare const foo: object | undefined;
declare const bar: () => object | null;

// Reported (and fixed).
const a1 = { ...(foo || {}) };
const a2 = { ...(foo ?? {}) };
const a3 = { a: 1, ...(bar() || {}), b: 2 };
const a4 = { ...((foo) || {}) };
const a5 = { ...((0, foo) || {}) };
const a6 = { ...(foo || ({})) };
const a7 = { ...foo || {} };

// Reported, not fixed (comments).
const b1 = { ...(foo || /* c */ {}) };
const b2 = { ...(foo || {/* c */}) };

// Not reported.
const k1 = { ...(foo && {}) };
const k2 = { ...(foo || { a: 1 }) };
const k3 = [...(foo as unknown as unknown[] || [])];
const k4 = { ...({} || foo) };
const k5 = Object.assign({}, foo || {});
export { a1, a2, a3, a4, a5, a6, a7, b1, b2, k1, k2, k3, k4, k5 };
