// Generates tests/collation_cases.txt: strings sorted by Node's `a.localeCompare(b)` (ICU's root
// collation, en-US), for collation/collation_test.v, which checks that collation.compare orders
// every pair it takes from them as Node does.
//
// The strings: every code point FractionalUCA.txt maps, the Han characters at the ends of the runs
// of the radical-stroke order and a fifth of the others, a sample of the other
// code points of every plane (unassigned, private use, noncharacters, lone surrogates), every
// contraction and prefix context of FractionalUCA.txt with variants (with a mark between, after
// another character, cut short), and random strings over pools of code points that interact
// (Latin with accents and case, combining marks of many classes, Greek, Cyrillic, Hebrew, Arabic,
// Indic, Thai and Lao, Tibetan, Hangul, kana, CJK, emoji, symbols, digits, compatibility
// characters, ignorables, special code points), with variants of each (case, accents, the order
// and the composition of the marks).
//
// The file: comment lines (#), then one string per line, sorted, after `<` (greater than the line
// before) or `=` (equal to it). A string has its characters as they are, but for `\u{X}` (a
// backslash, controls, line separators, noncharacters U+FFFE/U+FFFF, lone surrogates, U+FEFF).
// The pairs the test checks (each line with the WINDOW lines after it, and FAR pairs chosen by the
// LCG below) are also checked here against localeCompare, so that the order of the file gives
// Node's result for each of them.
//
// Node runs this script at development time only; veslint never runs Node.
//
// Usage: node tools/gen_collation_cases.mjs build/upstream/collation/FractionalUCA.txt > tests/collation_cases.txt
import fs from 'node:fs';

if (process.versions.icu !== '78.3' || process.versions.unicode !== '17.0') {
  throw new Error(`Node ${process.version} has ICU ${process.versions.icu} and Unicode ${process.versions.unicode}, not 78.3 and 17.0`);
}
const source = fs.readFileSync(process.argv[2], 'utf8');
const window = 4;
const farPairs = 200000;
const seed = 20261115;

let state = seed;
const random = count => {
  state = (Math.imul(state, 1103515245) + 12345) >>> 0;
  return (state >>> 8) % count;
};
const pick = list => list[random(list.length)];
const range = (a, b) => Array.from({ length: b - a + 1 }, (_, i) => a + i);
const text = points => points.map(cp => String.fromCharCode(...(cp >= 0x10000 ? [0xd800 + ((cp - 0x10000) >> 10), 0xdc00 + ((cp - 0x10000) & 0x3ff)] : [cp]))).join('');

const strings = new Set();
const add = points => strings.add(text(points));

// FractionalUCA.txt: its code points, contractions and prefixes; Han characters.
const singles = [];
const contractions = [];
const prefixed = [];
const han = [];
for (const raw of source.split('\n')) {
  if (raw.startsWith('[radical ') && !raw.startsWith('[radical end')) {
    const body = [...raw.slice(raw.indexOf(':') + 1, raw.lastIndexOf(']'))].map(c => c.codePointAt(0));
    for (let i = 0; i < body.length; i++) {
      if (body[i + 1] === 0x2d) {
        han.push(...range(body[i], body[i + 2]));
        i += 2;
      } else han.push(body[i]);
    }
    continue;
  }
  const line = raw.replace(/#.*/, '').trim();
  if (line === '' || line.startsWith('[')) continue;
  const m = /^([0-9A-F ]+?)\s*(?:\|\s*([0-9A-F ]+?))?\s*;/.exec(line);
  const first = m[1].split(' ').map(h => parseInt(h, 16));
  if (m[2] !== undefined) prefixed.push([first, m[2].split(' ').map(h => parseInt(h, 16))]);
  else if (first.length > 1) contractions.push(first);
  else singles.push(first[0]);
}
for (const cp of singles) add([cp]);
// Han characters: both ends of each run of code points of the same group of the radical-stroke
// order, and every fifth one.
{
  const isCore = cp => (cp >= 0x4e00 && cp <= 0x9fff) || (cp >= 0xf900 && cp <= 0xfaff);
  const key = cp => (isCore(cp) ? 0 : 0x200000) + cp;
  const group = new Map();
  let g = 0;
  for (let i = 0; i < han.length; i++) {
    if (i > 0 && key(han[i]) <= key(han[i - 1])) g++;
    group.set(han[i], g);
  }
  const sortedHan = [...han].sort((a, b) => a - b);
  for (let i = 0; i < sortedHan.length; i++) {
    const cp = sortedHan[i];
    const edge = i === 0 || i === sortedHan.length - 1 || sortedHan[i - 1] !== cp - 1 || sortedHan[i + 1] !== cp + 1 ||
      group.get(sortedHan[i - 1]) !== group.get(cp) || group.get(sortedHan[i + 1]) !== group.get(cp);
    if (edge || i % 5 === 0) add([cp]);
  }
}
const mapped = new Set([...singles, ...han]);
for (let cp = 0; cp <= 0x10ffff; cp += 0x3d) if (!mapped.has(cp)) add([cp]);
for (let cp = 0xd800; cp <= 0xdfff; cp += 0x1f) add([cp]);
for (const cp of [0xd800, 0xdbff, 0xdc00, 0xdfff, 0xfffd, 0xfffe, 0xffff, 0x10ffff, 0x10fffe, 0xe000, 0xf8ff, 0xf0000, 0x100000, 0xfdd0, 0xfdd1, 0xfdef, 0x1fffe, 0xe0001, 0xe0100]) {
  add([cp]);
}
for (let cp = 0xfdd0; cp <= 0xfdef; cp++) add([cp]);

// Pools for random strings.
const marks = [
  ...range(0x300, 0x36f), 0x483, 0x591, 0x5b0, 0x5b4, 0x5bc, 0x5c1, 0x5c2, 0x610, 0x64b, 0x64e, 0x651, 0x652, 0x653, 0x654, 0x655,
  0x670, 0x93c, 0x94d, 0x951, 0x9bc, 0x9cd, 0xa3c, 0xe31, 0xe34, 0xe38, 0xe39, 0xe3a, 0xe47, 0xe48, 0xe49, 0xe4a, 0xe4b, 0xe4c,
  0xeb8, 0xec8, 0xf71, 0xf72, 0xf74, 0xf7a, 0xf80, 0xf82, 0xf83, 0xf84, 0xf86, 0x1ab0, 0x1dc0, 0x1dce, 0x20d0, 0x20d2, 0x20e3,
  0x302a, 0x302b, 0x3099, 0x309a, 0xfe20, 0x1d165, 0x1d16d, 0x1e2ec, 0x16ff0, 0x05a2, 0x0315, 0x031b, 0x0345, 0x0334, 0x0338,
];
const latin = [...range(0x41, 0x5a), ...range(0x61, 0x7a), ...range(0xc0, 0x24f), 0x1e9e, 0xdf, 0x131, 0x130, 0x1e0a, 0x1e63, 0x1ea0, 0x1ef9, 0x2c65, 0xa7c0, 0xab30];
const ascii = range(0x20, 0x7e);
const scripts = [
  ...range(0x370, 0x3ff), ...range(0x1f00, 0x1f1f), ...range(0x400, 0x45f), 0x4e8, 0x4d9, ...range(0x5d0, 0x5ea), ...range(0x620, 0x64a),
  ...range(0x660, 0x669), ...range(0x905, 0x939), 0x958, 0x929, ...range(0x995, 0x9b9), 0x9cb, 0x9be, 0x9d7, ...range(0xb15, 0xb39), 0xb47, 0xb3e, 0xb56, 0xb57,
  ...range(0xbc6, 0xbcc), 0xbbe, 0xbd7, ...range(0xd46, 0xd4c), 0xd3e, 0xd57, 0xdd9, 0xdda, 0xddc, 0xdde, 0xdca, 0xdcf, 0xddf,
  ...range(0xe01, 0xe2e), ...range(0xe40, 0xe46), ...range(0xe81, 0xea3), ...range(0xec0, 0xec4), 0xedc, 0xedd,
  ...range(0xf40, 0xf6c), 0xfb2, 0xfb3, 0xf73, 0xf75, 0xf77, 0xf79, 0xf81, ...range(0x1000, 0x102a), 0x1025, 0x102e, 0x1031,
  ...range(0x10a0, 0x10ff), ...range(0x1200, 0x1248), ...range(0x13a0, 0x13f5), ...range(0x1780, 0x17b3), ...range(0x1950, 0x1974),
  ...range(0x19b0, 0x19c9), 0x1b05, 0x1b06, 0x1b35, ...range(0xaa80, 0xaac2), 0xaab5, 0xaab6, 0xaab9, 0xaabb, 0xaabc, 0x1611e, 0x1611f, 0x16120,
  0x16d63, 0x16d67, 0x114b9, 0x114b0, 0x114ba, 0x113c2, 0x113b8, 0x113c9, 0x11099, 0x1109a, 0x110ba, 0x11131, 0x11127, 0x1112e, 0x11347, 0x1133e, 0x11357,
  0x0cc6, 0x0cc2, 0x0cd5, 0x0cd6, 0x0cca, 0x0dd9, 0x0dcf, 0x0dca,
];
const hangul = [0xac00, 0xac01, 0xac1c, 0xb098, 0xd7a3, 0xd55c, ...range(0x1100, 0x1112), ...range(0x1161, 0x1175), ...range(0x11a8, 0x11c2), 0x3131, 0x314f, 0x1113, 0x11a7, 0x11ff, 0xa960, 0xd7b0];
const kana = [...range(0x3041, 0x3096), ...range(0x30a1, 0x30fa), 0x30fc, 0x30fd, 0x30fe, 0x309d, 0x309e, 0x3099, 0x309a, 0x309b, 0x309c, 0xff66, 0xff9e, 0x31f0, 0x1b000, 0x1b132];
const cjk = [0x4e00, 0x4e01, 0x4e8c, 0x4e36, 0x4e3f, 0x9fa5, 0x9fff, 0x3400, 0x3405, 0x4dbf, 0x20000, 0x2a6df, 0x2b740, 0x30000, 0x31350, 0xf900, 0xfa0e, 0xfa10,
  0xfa6d, 0x2f800, 0x2f00, 0x2f01, 0x2e80, 0x2e9f, 0x3007, 0x3005, 0x303b, 0x17000, 0x18b00, 0x1b170, 0x18d00, 0x3000, 0x3001, 0x3002, 0x300c, 0x3220, 0x3280,
  0x32ff, 0x3300, 0x337b, 0x1f200, 0x1f210];
const emoji = [0x1f600, 0x1f601, 0x1f44d, 0x1f3fb, 0x1f3ff, 0x200d, 0xfe0f, 0xfe0e, 0x2764, 0x1f468, 0x1f469, 0x1f466, 0x1f1fa, 0x1f1f8, 0x1f1e6, 0x2639,
  0x263a, 0x1f9d1, 0x1faf8, 0x1f004, 0xe0067, 0xe007f, 0x1f3f4, 0x20e3, 0x23];
const symbols = [...range(0xa1, 0xbf), 0xd7, 0xf7, ...range(0x2010, 0x2027), ...range(0x2030, 0x205e), ...range(0x20a0, 0x20c1), ...range(0x2100, 0x214f),
  ...range(0x2150, 0x2189), ...range(0x2190, 0x21ff), ...range(0x2200, 0x2262), ...range(0x2460, 0x24ff), ...range(0x2500, 0x2520), 0x25a0, 0x25cb, 0x2605,
  0x266a, 0x2713, 0x27e8, 0x2e3a, 0x3008, 0xfe50, ...range(0xff01, 0xff5e), 0xffe5, 0x1d400, 0x1d7ce, 0x1f100, 0x1f12f, 0x1d15e, 0x1d160, 0xfb01, 0xfb00,
  0xfdfa, 0x1f1, 0x2002, 0xa0, 0x2126, 0x212b, 0x212a, 0x2160, 0x216b, 0x2070, 0x2080, 0x1d2c, 0x02b0, 0x2c7c, 0x33a1, 0x3392, 0x0132, 0x0149, 0x01c4, 0x01c6,
  0x00b7, 0x0387, 0x013f, 0x0140, 0x02bc, 0x02bb];
const digits = [...range(0x30, 0x39), ...range(0x660, 0x669), ...range(0x966, 0x96f), ...range(0xe50, 0xe59), ...range(0xff10, 0xff19), ...range(0x1d7ce, 0x1d7d7),
  0x00b2, 0x00b9, 0x2081, 0x2460, 0x2474, 0x2488, 0x1f101, 0x0bf0, 0x1369, 0x3007, 0x4e00, 0x5341, 0x2155];
const ignorable = [0, 1, 0x7, 0x1b, 0x7f, 0x85, 0x9f, 0xad, 0x34f, 0x200b, 0x200c, 0x200d, 0x200e, 0x2060, 0x2061, 0x2064, 0xfeff, 0xfff9, 0xe0001, 0xe0020,
  0x180b, 0x180e, 0x061c, 0x115f, 0x1160, 0x3164, 0xffa0, 0x1bca0, 0x1d173, 0xfe00, 0xe0100, 0xe01ef];
const special = [0xfffd, 0xfffe, 0xffff, 0xfdd0, 0xfdd1, 0xfdef, 0xe000, 0xf8ff, 0xf0000, 0x10fffd, 0x10ffff, 0x0378, 0x0e3b, 0x2fffd, 0x3fffd, 0xe0080,
  0xd800, 0xdbff, 0xdc00, 0xdfff, 0xd83d, 0xde00, 0x9, 0xa, 0xd, 0x20, 0x3000, 0x1680, 0x2028, 0x2029, 0x5c];
const pools = [
  [latin, 30], [ascii, 20], [marks, 25], [scripts, 20], [hangul, 6], [kana, 6], [cjk, 6], [emoji, 5], [symbols, 10], [digits, 6], [ignorable, 6], [special, 5],
];
const poolTotal = pools.reduce((a, [, w]) => a + w, 0);
function randomCodePoint() {
  let r = random(poolTotal);
  for (const [pool, w] of pools) {
    if (r < w) return pick(pool);
    r -= w;
  }
  throw new Error('unreachable');
}
// Variants of a string: its case swapped, a mark added, removed or changed, the marks of a
// run reordered, its NFC and NFD, a character doubled.
function variants(points) {
  const s = text(points);
  const out = [s.toUpperCase(), s.toLowerCase(), s.normalize('NFC'), s.normalize('NFD'), s.normalize('NFKD')];
  const i = random(points.length + 1);
  out.push(text([...points.slice(0, i), pick(marks), ...points.slice(i)]));
  if (points.length > 1) {
    const j = random(points.length - 1);
    out.push(text([...points.slice(0, j), points[j + 1], points[j], ...points.slice(j + 2)]));
    out.push(text([...points.slice(0, j), ...points.slice(j + 1)]));
    out.push(text([...points.slice(0, j), pick(marks), ...points.slice(j + 1)]));
  }
  out.push(text([...points, points[points.length - 1]]));
  return out;
}

// Contractions and prefixes, with variants.
const someStarters = [0x61, 0x41, 0x4c, 0x6c, 0xe01, 0xe40, 0xf40, 0x30, 0x20, 0x4e00];
for (const cps of contractions) {
  add(cps);
  add(cps.slice(0, -1));
  add([...cps, pick(someStarters)]);
  add([pick(someStarters), ...cps]);
  add([...cps, pick(marks)]);
  for (let k = 1; k < cps.length; k++) {
    add([...cps.slice(0, k), pick(marks), ...cps.slice(k)]);
    add([...cps.slice(0, k), pick(marks), pick(marks), ...cps.slice(k)]);
  }
  add([...cps.slice(0, 1), ...cps.slice(1).reverse()]);
  for (const v of variants(cps)) strings.add(v);
}
for (const [prefix, cps] of prefixed) {
  add([...prefix, ...cps]);
  add([...prefix, pick(marks), ...cps]);
  add([...prefix, ...cps, ...prefix]);
  add([pick(someStarters), ...prefix, ...cps]);
  add(cps);
}

// Random strings, alone and mixed with ASCII words, and their variants.
for (let n = 0; n < 20000; n++) {
  const points = [];
  for (let k = 0, len = 1 + random(8); k < len; k++) points.push(randomCodePoint());
  add(points);
  if (n % 3 === 0) {
    const word = Array.from({ length: 1 + random(5) }, () => pick(latin.slice(0, 52)));
    add([...word, ...points]);
    add([...points, ...word]);
  }
  if (n % 4 === 0) for (const v of variants(points)) strings.add(v);
}
// ASCII strings (the fast path of collation.v).
for (let n = 0; n < 8000; n++) {
  const points = [];
  for (let k = 0, len = 1 + random(10); k < len; k++) points.push(random(5) === 0 ? random(128) : pick(ascii));
  add(points);
}

// Sort as Node does (a stable sort).
const sorted = [...strings].sort((a, b) => a.localeCompare(b));
const rank = new Array(sorted.length);
for (let i = 0; i < sorted.length; i++) {
  if (i === 0) rank[i] = 0;
  else {
    const c = sorted[i - 1].localeCompare(sorted[i]);
    if (c > 0) throw new Error('not sorted');
    rank[i] = rank[i - 1] + (c < 0 ? 1 : 0);
  }
}
// The pairs of the test, against localeCompare.
const check = (i, j) => {
  const want = Math.sign(rank[i] - rank[j]);
  if (Math.sign(sorted[i].localeCompare(sorted[j])) !== want || Math.sign(sorted[j].localeCompare(sorted[i])) !== -want) {
    throw new Error(`the order of the file does not give localeCompare for ${JSON.stringify(sorted[i])} and ${JSON.stringify(sorted[j])}`);
  }
};
let pairs = 0;
for (let i = 0; i < sorted.length; i++) {
  for (let d = 1; d <= window && i + d < sorted.length; d++) {
    check(i, i + d);
    pairs++;
  }
}
state = seed;
for (let n = 0; n < farPairs; n++) {
  check(random(sorted.length), random(sorted.length));
  pairs++;
}

const escape = s => {
  let out = '';
  for (let i = 0; i < s.length; i++) {
    let cp = s.charCodeAt(i);
    if (cp >= 0xd800 && cp <= 0xdbff && i + 1 < s.length) {
      const next = s.charCodeAt(i + 1);
      if (next >= 0xdc00 && next <= 0xdfff) {
        cp = 0x10000 + ((cp - 0xd800) << 10) + (next - 0xdc00);
        i++;
      }
    }
    const escaped = cp < 0x20 || cp === 0x5c || (cp >= 0x7f && cp <= 0x9f) || (cp >= 0xd800 && cp <= 0xdfff) || cp === 0x2028 || cp === 0x2029 ||
      cp === 0xfeff || cp === 0xfffe || cp === 0xffff;
    out += escaped ? `\\u{${cp.toString(16)}}` : String.fromCodePoint(cp);
  }
  return out;
};
const lines = [
  '# Generated by tools/gen_collation_cases.mjs; DO NOT EDIT.',
  `# ${sorted.length} strings sorted by a.localeCompare(b) of Node ${process.version} (ICU ${process.versions.icu}, CLDR ${process.versions.cldr}, Unicode ${process.versions.unicode}).`,
  `# window ${window}, far ${farPairs}, seed ${seed}: ${pairs} pairs checked against localeCompare in both orders.`,
];
for (let i = 0; i < sorted.length; i++) lines.push((i > 0 && rank[i] === rank[i - 1] ? '=' : '<') + escape(sorted[i]));
process.stdout.write(lines.join('\n') + '\n');
