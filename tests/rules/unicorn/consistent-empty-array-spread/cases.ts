declare const test: boolean;
declare const list: number[];
declare let s: string;
const ARR = [1, 2];
const STR = 'abc';

// Reported (and fixed).
const a1 = [...(test ? '' : [1, 2])];
const a2 = [...(test ? [1, 2] : '')];
const a3 = [...(test ? [] : 'abc')];
const a4 = [...(test ? 'abc' : [])];
const a5 = [...(test ? '' : ARR)];
const a6 = [...(test ? [] : STR)];
const a7 = [1, ...(test ? `` : [2])];
const a8 = [...(test ? '' : [1] as number[])];

// Reported, not fixed (a comment inside).
const b1 = [...(test ? [/* empty */] : 'abc')];

// Not reported.
const k1 = [...(test ? [] : [1])];
const k2 = [...(test ? '' : 'a')];
const k3 = [...(test ? '' : list)];
const k4 = [...(test ? [] : s)];
const k5 = [...(test ? 'x' : [1])];
const k6 = [...(test ? [] : s.repeat(2))];
const k7 = [...test ? '' : [1]];
const k8 = { ...(test ? '' : [1]) };
export { a1, a2, a3, a4, a5, a6, a7, a8, b1, k1, k2, k3, k4, k5, k6, k7, k8 };
