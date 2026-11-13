// Reported; the first report is fixed when every init is a literal.
var b = 1, a = 2;
let d = 'x', c = null, e = true, B = /re/;
const z: number = 1, y: string = 'y', x = 3;
var [first] = [1], second = 2, beta = 3, alpha = 4;
let g = 1, f = Math.max(1, 2);
let h = -1, gg = 2;
let \u0062c = 1, ac = 2;

// Not reported.
var aa = 1, bb = 2, cc;
let A = 1, a2 = 2;
const { k } = { k: 1 }, j = 2;
for (let i = 0, n = 1; i < n; i++) {}
export { a, b, c, d, e, B, x, y, z, first, second, alpha, beta, f, g, h, gg, bb, bc, ac, aa, cc, A, a2, j, k };
