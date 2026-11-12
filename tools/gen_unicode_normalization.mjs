// Generates rules/unicode_normalization_data.v and tests/unicode_normalization_cases.json: what
// String.prototype.normalize gives in the Node that runs this script (V8 and its ICU, the engine
// ESLint runs on), for rules/unicode_normalization.v. eslint-utils' getStaticValue calls
// `normalize` in the constant expressions the ported rules evaluate.
//
// Everything comes from normalize itself, not from the Unicode Character Database: the full
// decomposition of each code point is its NFD (or NFKD) alone; the order of the canonical
// combining classes is the order NFD puts two marks in; the primary composites are the
// decomposable code points NFC keeps. A copy of the algorithm of UAX #15 in this script, on those
// tables, must give what normalize gives for every code point, for every pair of a composition
// with a mark between, and for random strings, or the script stops.
//
// Node runs this script at development time only; veslint never runs Node.
//
// Usage: node tools/gen_unicode_normalization.mjs > rules/unicode_normalization_data.v && v fmt -w rules/unicode_normalization_data.v
import fs from 'node:fs';
import path from 'node:path';

const lastCodePoint = 0x10ffff;
const forms = ['NFC', 'NFD', 'NFKC', 'NFKD'];
const codePoints = text => [...text].map(c => c.codePointAt(0));
const text = points => String.fromCodePoint(...points);
const same = (a, b) => a.length === b.length && a.every((x, i) => x === b[i]);
const normalized = (points, form) => codePoints(text(points).normalize(form));
const hex = n => `U+${n.toString(16).toUpperCase().padStart(4, '0')}`;

// Hangul syllables are decomposed and composed by arithmetic (UAX #15, Hangul).
const hangul = { s: 0xac00, l: 0x1100, v: 0x1161, t: 0x11a7, lCount: 19, vCount: 21, tCount: 28 };
const nCount = hangul.vCount * hangul.tCount;
const sCount = hangul.lCount * nCount;
const isSyllable = cp => cp >= hangul.s && cp < hangul.s + sCount;
const isSurrogate = cp => cp >= 0xd800 && cp <= 0xdfff;

// The canonical combining classes, as an order: a code point is a mark (class other than 0) if NFD
// moves it past the mark of class 1 (U+0334) or the one of class 240 (U+0345), the lowest and the
// highest classes; two marks are in the order of their classes when NFD does not swap them.
const lowestMark = 0x334;
const highestMark = 0x345;
if (!same(normalized([highestMark, lowestMark], 'NFD'), [lowestMark, highestMark])) {
  throw new Error('U+0334 and U+0345 are not the lowest and the highest combining classes');
}
const canonical = new Map();
const compatibility = new Map();
const marks = [];
for (let cp = 0; cp <= lastCodePoint; cp++) {
  if (isSurrogate(cp)) {
    for (const form of forms) {
      if (!same(normalized([cp], form), [cp])) throw new Error(`the lone surrogate ${hex(cp)} changes`);
    }
    continue;
  }
  if (isSyllable(cp)) continue;
  const d = normalized([cp], 'NFD');
  const k = normalized([cp], 'NFKD');
  if (!same(d, [cp])) canonical.set(cp, d);
  if (!same(k, d)) compatibility.set(cp, k);
  if (same(d, [cp]) && (!same(normalized([cp, lowestMark], 'NFD'), [cp, lowestMark]) || !same(normalized([highestMark, cp], 'NFD'), [highestMark, cp]))) {
    marks.push(cp);
  }
}
// The class of `a` is above the one of `b` when NFD puts `b` first.
const compareClasses = (a, b) => {
  if (!same(normalized([a, b], 'NFD'), [a, b])) return 1;
  if (!same(normalized([b, a], 'NFD'), [b, a])) return -1;
  return 0;
};
marks.sort((a, b) => compareClasses(a, b) || a - b);
const rank = new Map();
let currentRank = 0;
for (let i = 0; i < marks.length; i++) {
  if (i === 0 || compareClasses(marks[i - 1], marks[i]) !== 0) currentRank++;
  rank.set(marks[i], currentRank);
}
if (currentRank >= 256) throw new Error(`${currentRank} combining classes do not fit in a byte`);
// The ranks give the order of NFD for every pair of marks.
for (const a of marks) {
  for (const b of marks) {
    const expected = Math.sign(rank.get(a) - rank.get(b));
    if (compareClasses(a, b) !== expected) throw new Error(`the ranks of ${hex(a)} and ${hex(b)} do not order them as NFD`);
  }
}
const classOf = cp => rank.get(cp) ?? 0;

// The primary composites: the decomposable code points NFC keeps. Each one is the composition of
// the code point its decomposition but the last code point composes to, and that last one.
const compositions = [];
for (const [cp, d] of canonical) {
  if (!same(normalized([cp], 'NFC'), [cp])) continue;
  const first = normalized(d.slice(0, -1), 'NFC');
  if (d.length < 2 || first.length !== 1) throw new Error(`${hex(cp)} is not the composition of a pair`);
  compositions.push([first[0], d[d.length - 1], cp]);
}
compositions.sort((a, b) => a[0] - b[0] || a[1] - b[1]);
for (let i = 1; i < compositions.length; i++) {
  if (compositions[i - 1][0] === compositions[i][0] && compositions[i - 1][1] === compositions[i][1]) {
    throw new Error(`two composites of ${hex(compositions[i][0])} ${hex(compositions[i][1])}`);
  }
}
const composed = new Map(compositions.map(([a, b, c]) => [`${a},${b}`, c]));

// UAX #15 on these tables: what rules/unicode_normalization.v does.
function decompose(points, compatible) {
  const out = [];
  for (const cp of points) {
    if (isSyllable(cp)) {
      const index = cp - hangul.s;
      out.push(hangul.l + Math.floor(index / nCount), hangul.v + Math.floor((index % nCount) / hangul.tCount));
      if (index % hangul.tCount !== 0) out.push(hangul.t + (index % hangul.tCount));
      continue;
    }
    const mapping = (compatible && compatibility.get(cp)) || canonical.get(cp);
    if (mapping) out.push(...mapping);
    else out.push(cp);
  }
  // The canonical ordering: a stable sort of each run of marks by class.
  for (let i = 1; i < out.length; i++) {
    const c = classOf(out[i]);
    if (c === 0) continue;
    for (let j = i; j > 0 && classOf(out[j - 1]) > c; j--) [out[j - 1], out[j]] = [out[j], out[j - 1]];
  }
  return out;
}
function composePair(a, b) {
  if (a >= hangul.l && a < hangul.l + hangul.lCount && b >= hangul.v && b < hangul.v + hangul.vCount) {
    return hangul.s + ((a - hangul.l) * hangul.vCount + (b - hangul.v)) * hangul.tCount;
  }
  if (isSyllable(a) && (a - hangul.s) % hangul.tCount === 0 && b > hangul.t && b < hangul.t + hangul.tCount) {
    return a + (b - hangul.t);
  }
  return composed.get(`${a},${b}`);
}
function compose(points) {
  if (points.length === 0) return points;
  const out = [points[0]];
  let starter = 0;
  // A mark at the start blocks nothing, and nothing composes with it.
  let lastClass = classOf(points[0]) === 0 ? 0 : 256;
  for (let i = 1; i < points.length; i++) {
    const cp = points[i];
    const c = classOf(cp);
    const composite = composePair(out[starter], cp);
    if (composite !== undefined && (lastClass < c || lastClass === 0)) {
      out[starter] = composite;
      continue;
    }
    if (c === 0) starter = out.length;
    lastClass = c;
    out.push(cp);
  }
  return out;
}
// The code points are those of the string in UTF-16: two halves of a pair are one code point.
function normalize(points, form) {
  const d = decompose(codePoints(text(points)), form === 'NFKC' || form === 'NFKD');
  return form === 'NFC' || form === 'NFKC' ? compose(d) : d;
}

// The strings the test checks besides the chosen ones, built the same way in
// rules/unicode_normalization_test.v: every code point alone; each composition with nothing, a
// mark of the lowest class, one of the highest and U+0301 between its two code points, and its
// composite followed by its second code point and by a mark of the lowest class; and random
// strings from a pool of code points that interact, in an order that depends only on the seed.
const pool = [
  0x41, 0x61, 0x43, 0x45, 0x4f, 0x55, 0x73, 0x3b1, 0x3b9, 0x3c9, 0x415, 0x627, 0x648, 0x928, 0x915, 0x995, 0xb47, 0xbc6, 0xbc7, 0xd46, 0xdd9,
  0x1025, 0x1b05, 0x1100, 0x1161, 0x1175, 0x11a8, 0x11c2, 0xac00, 0xac01, 0xd7a3, 0x304b, 0x30ab, 0x3046, 0x1e0a, 0x1e63, 0xc5, 0x212b, 0x2126,
  0x1e9b, 0xfb01, 0x2460, 0xff21, 0xbd, 0x2fa1d, 0xf900, 0x1d15e, 0x1d160, 0x11099, 0x1109a, 0x1d400, 0x3d3, 0x1f80, 0x390, 0x344, 0xf73,
  0xf75, 0xf77, 0xf81, 0x958, 0xfdfa, 0x1f1, 0x2002, 0xa0, 0x300, 0x301, 0x302, 0x303, 0x304, 0x306, 0x307, 0x308, 0x30a, 0x30b, 0x30c, 0x313,
  0x314, 0x31b, 0x323, 0x327, 0x328, 0x331, 0x334, 0x338, 0x342, 0x345, 0x5b0, 0x5b1, 0x5bc, 0x5c1, 0x5c2, 0x64b, 0x651, 0x653, 0x654, 0x655,
  0x670, 0x93c, 0x94d, 0x9be, 0x9d7, 0xb3e, 0xb56, 0xb57, 0xbbe, 0xbd7, 0xcd5, 0xcd6, 0xd3e, 0xd57, 0xdcf, 0xddf, 0xf71, 0xf72, 0xf74, 0xf80,
  0x102e, 0x1b35, 0x3099, 0x309a, 0x20d2, 0x1dce, 0x1d165, 0x1d16d, 0x110ba, 0xd800, 0xdc00, 0x20, 0x2e, 0x10400,
];
const seed = 20261111;
const randomCount = 20000;
const maxLength = 8;
function randomStrings() {
  let state = seed;
  const random = count => {
    state = (Math.imul(state, 1103515245) + 12345) >>> 0;
    return (state >>> 8) % count;
  };
  const out = [];
  for (let i = 0; i < randomCount; i++) {
    const points = [];
    for (let j = 0, n = 1 + random(maxLength); j < n; j++) points.push(pool[random(pool.length)]);
    out.push(points);
  }
  return out;
}
const compositionStrings = compositions.flatMap(([a, b, c]) => [[a, b], [a, lowestMark, b], [a, highestMark, b], [a, 0x301, b], [c, b], [c, lowestMark]]);

// FNV-1a over the UTF-16 units of each result, and a separator after each one.
function digest(strings, form) {
  let h = 0x811c9dc5;
  for (const points of strings) {
    const result = text(points).normalize(form);
    for (let i = 0; i < result.length; i++) h = Math.imul(h ^ result.charCodeAt(i), 0x01000193) >>> 0;
    h = Math.imul(h ^ 0x10000, 0x01000193) >>> 0;
  }
  return h.toString(16).padStart(8, '0');
}
const blockSize = 0x1000;
const chunkSize = 1000;
const chunks = (list, size) => Array.from({ length: Math.ceil(list.length / size) }, (_, i) => list.slice(i * size, (i + 1) * size));
const blocks = Array.from({ length: (lastCodePoint + 1) / blockSize }, (_, i) => Array.from({ length: blockSize }, (_, j) => [i * blockSize + j]));
const random = randomStrings();
const digests = {};
for (const form of forms) {
  digests[form] = {
    blocks: blocks.map(block => digest(block, form)),
    compositions: chunks(compositionStrings, chunkSize).map(chunk => digest(chunk, form)),
    random: chunks(random, chunkSize).map(chunk => digest(chunk, form)),
  };
}

// The copy of the algorithm gives what normalize gives on all of them.
for (const strings of [...blocks, compositionStrings, random]) {
  for (const points of strings) {
    for (const form of forms) {
      if (!same(normalize(points, form), normalized(points, form))) {
        throw new Error(`${form} of ${points.map(hex).join(' ')}: the tables give ${normalize(points, form).map(hex).join(' ')}, normalize ${normalized(points, form).map(hex).join(' ')}`);
      }
    }
  }
}

// Chosen strings, with their four forms as UTF-16 units.
const chosen = [
  '', 'abc', 'Å', 'Å', 'Å', 'Ω', 'ﬁ', 'ﬃ', '①', 'Ａ', '½', 'é', 'é', 'ẛ̣', 'ṩ', 'ḍ̇', 'ḍ̇', 'q̣̇', '한글', '한', '가', '가', '각', '각',
  'ᄀ́ᅡ', 'Ǻ', 'ΐ', 'ᾀ', '̈́', 'ཱི', 'ཱུ', 'क़', 'ﷺ', 'Ǳ', ' ', ' ', 'が', 'ガ', '𝅗𝅥',
  '\u{1d15e}', '\u{11099}\u{110ba}', '\u{2fa1d}', '豈', 'ą́', 'ą́', 'á̴', 'áͅ', '́a', '̨́',
  '\ud800', 'a\udc00', '\ud800́', 'ୋ', 'ୌ', 'ொ', 'ൊ', 'ො', 'ဦ', 'Ä̈',
  'ǅ', 'ﬅ', '㌀', '㍻', '℃', 'Ⅻ', '𝐀', 'ẛ', 'ẛ̣', 'à́̂̃̄̅̆', 'é́', '̀̀a',
];
const units = value => Array.from({ length: value.length }, (_, i) => value.charCodeAt(i));
const cases = chosen.map(value => ({
  units: units(value),
  nfc: units(value.normalize('NFC')),
  nfd: units(value.normalize('NFD')),
  nfkc: units(value.normalize('NFKC')),
  nfkd: units(value.normalize('NFKD')),
}));
fs.writeFileSync(
  path.resolve(import.meta.dirname, '../tests/unicode_normalization_cases.json'),
  JSON.stringify({ node: process.version, icu: process.versions.icu, unicode: process.versions.unicode, cases, blockSize, chunkSize, seed, randomCount, maxLength, pool, digests }) + '\n',
);

// The type of the array is the one of its first element.
const list = values => `[${values.map((n, i) => (i === 0 ? `u32(0x${n.toString(16)})` : `0x${n.toString(16)}`)).join(', ')}]`;
// A table of mappings: the sorted code points, the start of the mapping of each one in the data
// (and the end of the last), and the data.
function mappingTable(map) {
  const keys = [...map.keys()].sort((a, b) => a - b);
  const starts = [0];
  const data = [];
  for (const key of keys) {
    data.push(...map.get(key));
    starts.push(data.length);
  }
  return { keys, starts, data };
}
const nfd = mappingTable(canonical);
const nfkd = mappingTable(compatibility);
const ranks = [...rank.entries()].sort((a, b) => a[0] - b[0]).flat();
const out = [
  '// Code generated by tools/gen_unicode_normalization.mjs; DO NOT EDIT.',
  '',
  'module rules',
  '',
  `// The normalization of the strings of Node ${process.version} (V8 ${process.versions.v8}, ICU ${process.versions.icu}, Unicode ${process.versions.unicode}).`,
  '',
  `// The code points whose canonical combining class is not 0, as pairs sorted by the code point: the`,
  `// code point and the rank of its class (1 for the lowest of the ${currentRank} classes).`,
  `const unicode_class_ranks = ${list(ranks)}`,
  '',
  '// The full canonical decomposition of the code points that have one (NFD of the code point alone),',
  '// Hangul syllables aside: the sorted code points, the start of the decomposition of each one in',
  '// the data, and the end of the last one.',
  `const unicode_nfd_keys = ${list(nfd.keys)}`,
  '',
  `const unicode_nfd_starts = ${list(nfd.starts)}`,
  '',
  `const unicode_nfd_data = ${list(nfd.data)}`,
  '',
  '// The same for the full compatibility decompositions (NFKD of the code point alone) that are',
  '// not the canonical one.',
  `const unicode_nfkd_keys = ${list(nfkd.keys)}`,
  '',
  `const unicode_nfkd_starts = ${list(nfkd.starts)}`,
  '',
  `const unicode_nfkd_data = ${list(nfkd.data)}`,
  '',
  '// The primary composites, Hangul syllables aside: triples of the first code point, the second',
  '// and the composite, sorted by the first two.',
  `const unicode_compositions = ${list(compositions.flat())}`,
  '',
];
process.stdout.write(out.join('\n'));
process.stderr.write(`${marks.length} marks in ${currentRank} classes, ${nfd.keys.length} canonical and ${nfkd.keys.length} compatibility decompositions, ${compositions.length} compositions\n`);
