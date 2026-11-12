// Generates tests/math_cases.json for rules/js_math_test.v: what the transcendental functions of
// Math give in the Node that runs this script (V8's ieee754.cc and Math.hypot), as the bits of the
// doubles: for chosen arguments one by one, and for arguments built from a seed, as digests per
// function and kind of argument. rules/js_math.v must give the same bits.
//
// The arguments from the seed are built the same way in rules/js_math_test.v: a linear congruential
// generator of 32-bit numbers, and doubles made from its numbers with exact operations only (bits,
// or a product by a power of two and one addition).
//
// Node runs this script at development time only; veslint never runs Node.
//
// Usage: node tools/gen_math_cases.mjs
import fs from 'node:fs';
import path from 'node:path';

const unary = ['acos', 'acosh', 'asin', 'asinh', 'atan', 'atanh', 'cbrt', 'cos', 'cosh', 'exp', 'expm1', 'log', 'log1p', 'log2', 'log10', 'sin', 'sinh', 'tan', 'tanh'];
const seed = 20261111;
const perMode = 40000;
const chunkSize = 10000;

const buffer = new ArrayBuffer(8);
const float = new Float64Array(buffer);
const words = new Uint32Array(buffer);
const fromWords = (hi, lo) => {
  words[0] = lo >>> 0;
  words[1] = hi >>> 0;
  return float[0];
};
// The bits of a result, with one NaN for all of them.
const bitsOf = x => {
  if (Number.isNaN(x)) return [0, 0x7ff80000];
  float[0] = x;
  return [words[0], words[1]];
};
const hex = x => {
  const [lo, hi] = bitsOf(x);
  return hi.toString(16).padStart(8, '0') + lo.toString(16).padStart(8, '0');
};

class Generator {
  constructor(start) {
    this.state = start >>> 0;
  }
  next() {
    this.state = (Math.imul(this.state, 1103515245) + 12345) >>> 0;
    return this.state;
  }
  // A fraction in [0, 1) with 32 bits.
  unit() {
    return this.next() / 4294967296;
  }
}

// The kinds of arguments, by name: rules/js_math_test.v has the same.
const specials = [0, -0, NaN, Infinity, -Infinity, 1, -1, 0.5, -0.5, 2, -2, 1e-300, 5e-324, -5e-324, 2.2250738585072014e-308, Number.MAX_VALUE, -Number.MAX_VALUE];
const modes = {
  // Any double, NaNs and infinities among them.
  bits: g => fromWords(g.next(), g.next()),
  // [-1, 1], [-16, 16] and [-750, 750].
  unit: g => g.unit() * 2 - 1,
  small: g => g.unit() * 32 - 16,
  exp: g => g.unit() * 1500 - 750,
  // A random significand with an exponent from -60 to 60, and with one from 0 to 1023.
  wide: g => fromWords((g.next() & 0x80000000) | ((1023 - 60 + (g.next() % 121)) << 20) | (g.next() & 0xfffff), g.next()),
  huge: g => fromWords((g.next() & 0x80000000) | ((1023 + (g.next() % 1024)) << 20) | (g.next() & 0xfffff), g.next()),
  // Next to a multiple of pi/2, and next to 1.
  pio2: g => ((g.next() % 200001) - 100000) * 1.5707963267948966 + (g.unit() - 0.5) * 9.313225746154785e-10,
  near1: g => 1 + (g.unit() - 0.5) * 9.5367431640625e-7,
};
const values = (mode, count, start) => {
  const g = new Generator(start);
  return Array.from({ length: count }, () => modes[mode](g));
};

// FNV-1a over the two words of each result, the less significant first.
function digest(results) {
  let h = 0x811c9dc5;
  for (const x of results) {
    const [lo, hi] = bitsOf(x);
    h = Math.imul(h ^ lo, 0x01000193) >>> 0;
    h = Math.imul(h ^ hi, 0x01000193) >>> 0;
  }
  return h.toString(16).padStart(8, '0');
}
const chunks = list => Array.from({ length: Math.ceil(list.length / chunkSize) }, (_, i) => list.slice(i * chunkSize, (i + 1) * chunkSize));

const modeNames = Object.keys(modes);
// Each kind of argument starts from its own state: the seed plus its index.
const inputs = Object.fromEntries(modeNames.map((mode, i) => [mode, values(mode, perMode, seed + i)]));
const digests = {};
for (const name of unary) {
  digests[name] = Object.fromEntries(modeNames.map(mode => [mode, chunks(inputs[mode].map(Math[name])).map(digest)]));
}
// atan2 of pairs of the same kind (y first), and of every pair of special arguments.
digests.atan2 = Object.fromEntries(
  modeNames.map((mode, i) => {
    const ys = values(mode, perMode, seed + 100 + i);
    const xs = values(mode, perMode, seed + 200 + i);
    return [mode, chunks(ys.map((y, j) => Math.atan2(y, xs[j]))).map(digest)];
  }),
);
// hypot of 0 to 6 arguments: one of the special ones one time in eight, else a `wide` one.
function hypotArguments(count) {
  const g = new Generator(seed + 300);
  return Array.from({ length: count }, () => Array.from({ length: g.next() % 7 }, () => (g.next() % 8 === 0 ? specials[g.next() % specials.length] : modes.wide(g))));
}
digests.hypot = { mixed: chunks(hypotArguments(perMode).map(args => Math.hypot(...args))).map(digest) };

// Chosen arguments: the special ones and the thresholds of the functions, with each result.
const chosen = [
  ...specials,
  Math.PI, Math.PI / 2, Math.PI / 4, (3 * Math.PI) / 4, 2 ** 19 * (Math.PI / 2), 1e22, 2 ** 28, 2 ** -28, 2 ** -27, 2 ** -54, 2 ** -1022, 2 ** 66,
  709.782712893384, 709.7827128933841, -745.1332191019411, -745.1332191019412, 22, -22, 0.34657359027997264, 1.0397207708399179, 710.4758600739439,
  710.475860073944, 0.975, -0.975, 0.4375, 2.4375, 1.1875, 0.6875, 0.6744, 0.3, 0.78125, 1e-10, -1e-10, 56 * Math.LN2, -56 * Math.LN2, 1.0000000000000002,
  0.9999999999999999, Math.SQRT2, Math.SQRT1_2, 10, 100, 1000, 1e15, 3, 27, -8, 1e308,
];
const cases = {};
for (const name of unary) cases[name] = chosen.map(x => [hex(x), hex(Math[name](x))]);
cases.atan2 = [...specials, Math.PI, 1e22, 2 ** -1022, 22].flatMap(y => specials.map(x => [hex(y), hex(x), hex(Math.atan2(y, x))]));
const hypotCases = [[], [3, 4], [-3], [NaN, Infinity], [Infinity, NaN], [NaN, 1], [0, -0], [1e308, 1e308], [3, 4, 12], [1, 2, 3, 4], [1, NaN, Infinity, 2], [5e-324, 5e-324], [1e-300, 1e-300, 1e-300, 1e-300, 1e-300]];
cases.hypot = hypotCases.map(args => [args.map(hex), hex(Math.hypot(...args))]);

fs.writeFileSync(
  path.resolve(import.meta.dirname, '../tests/math_cases.json'),
  JSON.stringify({ node: process.version, v8: process.versions.v8, seed, perMode, chunkSize, modes: modeNames, specials: specials.map(hex), cases, digests }) + '\n',
);
process.stderr.write(`${unary.length + 2} functions, ${modeNames.length} kinds of arguments of ${perMode} each\n`);
