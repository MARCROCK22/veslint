declare const v: any;

// Reported.
const a = { x: 1, x: 2 };
const b = { 'y': 1, y: 2 };
const c = { 1: 1, '1': 2 };
const d = { 0x1: 1, 1: 2 };
const e = { z: 1, get z() { return 1; } };
const f = { get w() { return 1; }, get w() { return 2; } };
const g = { set w(_: number) {}, set w(_: number) {} };
const h = { m() {}, m() {} };
const i = { v, v };
const j = { ['k']: 1, k: 2 };
const k = { [`t`]: 1, t: 2 };
const l = { __proto__: null, ['__proto__']: null, '__proto__': null };

// Not reported.
const m = { get u() { return 1; }, set u(_: number) {} };
const n = { __proto__: null, '__proto__': v };
const p = { [v]: 1, [v]: 2 };
const q = { a: 1, b: 2 };
const r = { ...v, ...v };
