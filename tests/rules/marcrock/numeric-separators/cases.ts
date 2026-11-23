// Reported: digits not grouped by three.
const a = 1000;
const b = 1000000;
const c = 1234567.5;
const d = 1.12345;
const e = 12345.67891;
const f = 1000n;
const g = 123456789n;
const h = 1_0;
const i = 10_00;
const j = 1_00_000;
const k = 5.;
const l = 1000.;
const m = 0.0001;
const r = 1E5;
const v = 1000.000_0;
const w = [1000, 2000, 300];
const x = -1000;
const y = { 1000: 'a', 10000: 'b' };
const z = 1000 as number;
type A = 1000;
enum B { C = 10000 }
const aa = .12345;
const ab = 0.1234;

// Not reported.
const ba = 1;
const bb = 12;
const bc = 100;
const bd = 1_000;
const be = 1_000_000;
const bf = 0x1000;
const bg = 0b1010;
const bh = 1e5;
const bi = 1.5;
const bj = 1_234.567_8;
const bk = '1000';
const bl = 1n;
const bm = 999n;
const bn = 0xFFFFFFn;
const bo = 1.5e10;
const bp = 1_000n;
const bq = .5;
const br = 0;
const bs = 1.123;
const bt = 0b1111_0000;

// Not reported on purpose: a literal with a prefix, in either case and as a BigInt too, or with an
// exponent written `E`. @marcrock22/eslintcf 0.0.2 reports these and fixes them into code that
// does not parse (`0o_755`, `0X_123_456`, `1E_123`); ESLint's findings are in limitations.txt and
// fixes.known.txt (MARCROCK22/veslint#38).
const ca = 0o755;
const cb = 0o755n;
const cc = 0O777777;
const cd = 0B101010;
const ce = 0X123456;
const cf = 0O7777;
const cg = 0o7777;
const ch = 0X1000;
const ci = 0B1010101;
const cj = 1234E5;
const ck = 1E123;
const cl = 0B101010n;
const cm = 0X123456n;
const cn = 0o1234567;
const co = 12345.5E10;

export { a, b, c, d, e, f, g, h, i, j, k, l, m, r, v, w, x, y, z, aa, ab, ba, bb, bc, bd, be, bf, bg, bh, bi, bj, bk, bl, bm, bn, bo, bp, bq, br, bs, bt };
export { ca, cb, cc, cd, ce, cf, cg, ch, ci, cj, ck, cl, cm, cn, co };
export type { A };
export { B };
