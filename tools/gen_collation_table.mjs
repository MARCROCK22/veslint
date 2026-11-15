// Generates collation/table.v: the data of collation/collation.v, which compares strings as Node's
// `a.localeCompare(b)` does (ICU's root collation, which the en-US locale uses, at its default
// strength, tertiary).
//
// The collation elements come from ICU's own source of its root collation, FractionalUCA.txt of
// ICU 78.3 (UCA 17.0.0, CLDR 48), which tools/unicode/c/genuca/genuca.cpp builds ucadata.icu from,
// read as genuca and CollationBaseDataBuilder read it:
// - a mapping `XXXX YYYY; [p, s, t][…]` gives the collation elements of a code point or of a
//   contraction, `XXXX | YYYY; […]` those of YYYY after the prefix XXXX; a weight is up to four
//   bytes (primary) or two (secondary, tertiary), left-aligned; `[U+XXXX…]` is the element of
//   another code point (a Han character), with the secondary and tertiary weights after it, if any;
// - contractions that start with U+FDD0 only feed the inverse table (not compared strings);
//   U+FDD1 U+FDD0 is the first unassigned primary (FE040200); U+FFFD, U+FFFE and U+FFFF have
//   fixed elements (FFFD0505, the merge separator 02000505, FFFF0505);
// - Han characters (Unified_Ideograph) are in the radical-stroke order of the [radical] lines
//   (Node's ICU data is "ucadata-unihan", the default of ICU's data build), with primaries above
//   every explicit one and below the unassigned code points (Collation::unassignedPrimaryFromCodePoint:
//   by code point, after a gap before U+0000), which also covers lone surrogates.
// The comparison (CollationCompare::compareUpToQuaternary at tertiary strength, no reordering, no
// variable weighting) only orders the weights of each level, so the weights are replaced by their
// ranks: primaries by rank among the explicit ones (Han, unassigned and special primaries above
// them, see the constants below), secondaries by rank, tertiaries by rank after the mask of
// ICU's tertiary comparison without case first (0x3f3f, which drops the case bits).
//
// Node normalizes (V8 turns ICU's normalization mode on), the way of ICU's
// FCDUTF16CollationIterator: the text is read as it is where it passes the FCD check, and only
// the segments that fail it are replaced by their NFD; so the table keeps every mapping (those of
// precomposed characters and contractions that are not in NFD are used on FCD text), and the
// canonical decompositions and the order of the canonical combining classes, for the FCD check and
// the NFD of the segments, come from String.prototype.normalize of the Node that runs this script,
// as tools/gen_unicode_normalization.mjs takes them.
//
// The data is a stream of unsigned numbers, five bits per character of a 64-character alphabet,
// the sixth bit set on every character but the last of a number (collation.v decodes it).
//
// Node runs this script at development time only; veslint never runs Node.
//
// Usage: node tools/gen_collation_table.mjs build/upstream/collation/FractionalUCA.txt > collation/table.v && v fmt -w collation/table.v
// (FractionalUCA.txt: https://raw.githubusercontent.com/unicode-org/icu/release-78.3/icu4c/source/data/unidata/FractionalUCA.txt)
import fs from 'node:fs';

if (process.versions.icu !== '78.3' || process.versions.unicode !== '17.0') {
  throw new Error(`Node ${process.version} has ICU ${process.versions.icu} and Unicode ${process.versions.unicode}, not 78.3 and 17.0`);
}
const source = fs.readFileSync(process.argv[2], 'utf8');
const hex = n => `U+${n.toString(16).toUpperCase().padStart(4, '0')}`;
const codePoints = text => [...text].map(c => c.codePointAt(0));
const text = points => String.fromCodePoint(...points);
const same = (a, b) => a.length === b.length && a.every((x, i) => x === b[i]);
const nfd = points => codePoints(text(points).normalize('NFD'));
const isSurrogate = cp => cp >= 0xd800 && cp <= 0xdfff;
const isSyllable = cp => cp >= 0xac00 && cp <= 0xd7a3;

// The primaries of collation.v above the ranks of the explicit ones (these constants are also
// written to table.v).
const hanBase = 2 ** 16;
const hanGroupShift = 2 ** 22;
const unassignedBase = 2 ** 40;
const fffdPrimary = 2 ** 41;
const ffffPrimary = 2 ** 41 + 1;

// --- Han: the radical-stroke order. ---
// Each [radical] line lists Han characters and ranges; the order is the order of the lines and of
// the characters in them. A group is a run of characters in increasing order of `hanKey` (the
// UCA's implicit order: the core ideographs, then the others, by code point); a Han primary is
// the group, then the key.
const isCoreHan = cp => (cp >= 0x4e00 && cp <= 0x9fff) || (cp >= 0xf900 && cp <= 0xfaff);
const hanKey = cp => (isCoreHan(cp) ? 0 : 0x200000) + cp;
const hanGroup = new Map();
let unifiedIdeographs = null;
{
  let group = -1;
  let ended = false;
  for (const line of source.split('\n')) {
    if (line.startsWith('[Unified_Ideograph ')) {
      unifiedIdeographs = new Set();
      for (const range of line.slice(19, line.indexOf(']')).trim().split(/\s+/)) {
        const [a, b] = range.split('..').map(h => parseInt(h, 16));
        for (let cp = a; cp <= (b ?? a); cp++) unifiedIdeographs.add(cp);
      }
      continue;
    }
    if (!line.startsWith('[radical ')) continue;
    if (line.startsWith('[radical end]')) {
      ended = true;
      continue;
    }
    const body = codePoints(line.slice(line.indexOf(':') + 1, line.lastIndexOf(']')));
    let previous = Infinity;
    for (let i = 0; i < body.length; i++) {
      const start = body[i];
      let end = start;
      if (body[i + 1] === 0x2d) {
        end = body[i + 2];
        i += 2;
      }
      for (let cp = start; cp <= end; cp++) {
        if (hanGroup.has(cp)) throw new Error(`${hex(cp)} twice in the radical-stroke order`);
        if (hanKey(cp) <= previous) group++;
        hanGroup.set(cp, group);
        previous = hanKey(cp);
      }
    }
  }
  if (!ended || !unifiedIdeographs) throw new Error('no [Unified_Ideograph] line or no [radical end]');
  if (hanGroup.size !== unifiedIdeographs.size || [...unifiedIdeographs].some(cp => !hanGroup.has(cp))) {
    throw new Error('the radical-stroke order does not list exactly the Unified_Ideograph characters');
  }
  if (group >= 2 ** 18) throw new Error('too many Han groups');
}
const hanPrimary = cp => hanBase + hanGroup.get(cp) * hanGroupShift + hanKey(cp);

// --- The mappings. ---
function weight(field, maxBytes) {
  const bytes = field.trim() === '' ? [] : field.trim().split(/\s+/).map(h => parseInt(h, 16));
  if (bytes.length > maxBytes || bytes.some(b => !(b >= 0 && b <= 255))) throw new Error(`bad weight "${field}"`);
  let w = 0;
  for (let i = 0; i < maxBytes; i++) w = w * 256 + (bytes[i] ?? 0);
  return w;
}
const common = 0x0500;
// A collation element: {p, s, t}, p a 32-bit explicit primary or {han: cp} or {fixed: primary}.
const singles = new Map(); // code point -> elements
const contractions = []; // [code points, elements]
const prefixed = []; // [prefix code points, code point, elements]
function singleElement(cp) {
  if (singles.has(cp)) {
    const ces = singles.get(cp);
    if (ces.length !== 1) throw new Error(`[${hex(cp)}] is not one element`);
    return ces[0];
  }
  if (hanGroup.has(cp)) return { p: { han: cp }, s: common, t: common };
  throw new Error(`[${hex(cp)}] has no element`);
}
function parseElements(field) {
  const out = [];
  const re = /\[([^\]]*)\]/g;
  let m;
  let rest = field;
  while ((m = re.exec(field))) {
    const parts = m[1].split(',');
    if (parts[0].trim().startsWith('U+')) {
      const base = singleElement(parseInt(parts[0].trim().slice(2), 16));
      if (parts.length === 1) out.push({ ...base });
      else if (parts.length === 2) out.push({ ...base, t: weight(parts[1], 2) });
      else if (parts.length === 3) out.push({ ...base, s: weight(parts[1], 2), t: weight(parts[2], 2) });
      else throw new Error(`bad element ${m[0]}`);
    } else {
      if (parts.length !== 3) throw new Error(`bad element ${m[0]}`);
      out.push({ p: weight(parts[0], 4), s: weight(parts[1], 2), t: weight(parts[2], 2) });
    }
    rest = rest.replace(m[0], '');
  }
  if (rest.trim() !== '' || out.length === 0) throw new Error(`bad elements "${field}"`);
  return out;
}
for (const raw of source.split('\n')) {
  const line = raw.replace(/#.*/, '').trim();
  if (line === '' || line.startsWith('[')) continue;
  const m = /^([0-9A-F]+(?: [0-9A-F]+)*)\s*(?:\|\s*([0-9A-F]+(?: [0-9A-F]+)*))?\s*;\s*(\[.*\])$/.exec(line);
  if (!m) throw new Error(`cannot read "${raw}"`);
  const first = m[1].split(' ').map(h => parseInt(h, 16));
  const prefix = m[2] === undefined ? null : first;
  const cps = m[2] === undefined ? first : m[2].split(' ').map(h => parseInt(h, 16));
  if (cps[0] === 0xfdd0 && cps.length > 1) continue; // inverse table only
  if (cps.length === 1 && cps[0] >= 0xfffd && cps[0] <= 0xffff) continue; // fixed below
  if (cps.length === 2 && cps[0] === 0xfdd1 && cps[1] === 0xfdd0) continue; // fixed below
  const ces = parseElements(m[3]);
  if (prefix) prefixed.push([prefix, cps, ces]);
  else if (cps.length > 1) contractions.push([cps, ces]);
  else {
    if (singles.has(cps[0])) throw new Error(`${hex(cps[0])} twice`);
    singles.set(cps[0], ces);
  }
}
const mergeSeparator = 0x02000000;
singles.set(0xfffd, [{ p: { fixed: fffdPrimary }, s: common, t: common }]);
singles.set(0xfffe, [{ p: mergeSeparator, s: common, t: common }]);
singles.set(0xffff, [{ p: { fixed: ffffPrimary }, s: common, t: common }]);
contractions.push([[0xfdd1, 0xfdd0], [{ p: { fixed: unassignedBase }, s: common, t: common }]]);

// --- Ranks. ---
const allElements = [...singles.values(), ...contractions.map(c => c[1]), ...prefixed.map(p => p[2])].flat();
const ranks = values => {
  const sorted = [...new Set([0, ...values])].sort((a, b) => a - b);
  return new Map(sorted.map((v, i) => [v, i]));
};
const primaryRank = ranks(allElements.filter(e => typeof e.p === 'number').map(e => e.p));
const tertiaryMask = t => t & 0x3f3f;
for (const e of allElements) {
  if (tertiaryMask(e.t) === 0 && e.t !== 0) throw new Error('a tertiary weight that is only case bits');
  if (e.p === 0 && e.s === 0 && e.t !== 0 && tertiaryMask(e.t) === 0) throw new Error('bad element');
}
const secondaryRank = ranks(allElements.map(e => e.s));
const tertiaryRank = ranks(allElements.map(e => tertiaryMask(e.t)));
if (primaryRank.size > hanBase) throw new Error(`${primaryRank.size} explicit primaries`);
if (secondaryRank.size > 512) throw new Error(`${secondaryRank.size} secondaries`);
if (tertiaryRank.size > 32) throw new Error(`${tertiaryRank.size} tertiaries`);
// The primary of an element in collation.v: null for a Han reference (computed from its code point).
const finalPrimary = e => (typeof e.p === 'number' ? primaryRank.get(e.p) : e.p.fixed ?? null);
const st = e => secondaryRank.get(e.s) * 32 + tertiaryRank.get(tertiaryMask(e.t));
// The (secondary, tertiary) pairs, most frequent first.
const stCount = new Map();
for (const e of allElements) stCount.set(st(e), (stCount.get(st(e)) ?? 0) + 1);
const palette = [...stCount.keys()].sort((a, b) => stCount.get(b) - stCount.get(a) || a - b);
const paletteIndex = new Map(palette.map((v, i) => [v, i]));

// --- Normalization data. ---
const lowestMark = 0x334;
const highestMark = 0x345;
const canonical = new Map();
const marks = [];
for (let cp = 0; cp <= 0x10ffff; cp++) {
  if (isSurrogate(cp) || isSyllable(cp)) continue;
  const d = nfd([cp]);
  if (!same(d, [cp])) {
    canonical.set(cp, d);
    continue;
  }
  if (!same(nfd([cp, lowestMark]), [cp, lowestMark]) || !same(nfd([highestMark, cp]), [highestMark, cp])) marks.push(cp);
}
const compareClasses = (a, b) => {
  if (!same(nfd([a, b]), [a, b])) return 1;
  if (!same(nfd([b, a]), [b, a])) return -1;
  return 0;
};
marks.sort((a, b) => compareClasses(a, b) || a - b);
const classRank = new Map();
{
  let current = 0;
  for (let i = 0; i < marks.length; i++) {
    if (i === 0 || compareClasses(marks[i - 1], marks[i]) !== 0) current++;
    classRank.set(marks[i], current);
  }
  for (const a of marks) {
    for (const b of marks) {
      if (compareClasses(a, b) !== Math.sign(classRank.get(a) - classRank.get(b))) throw new Error(`the ranks of ${hex(a)} and ${hex(b)}`);
    }
  }
}

// --- Encoding. ---
const alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
class Stream {
  constructor() {
    this.chars = [];
  }
  num(n) {
    if (!Number.isSafeInteger(n) || n < 0) throw new Error(`cannot encode ${n}`);
    do {
      const digit = n % 32;
      n = Math.floor(n / 32);
      this.chars.push(alphabet[digit + (n > 0 ? 32 : 0)]);
    } while (n > 0);
  }
  signed(n) {
    this.num(n >= 0 ? n * 2 : -n * 2 - 1);
  }
  toString() {
    const lines = [];
    for (let i = 0; i < this.chars.length; i += 100) lines.push(this.chars.slice(i, i + 100).join(''));
    return lines.join('\n');
  }
}
// Elements: the primary as a difference from the last primary written (Han references: their code
// point, flagged in the lowest bit), then the index of the (secondary, tertiary) pair.
function writeElements(out, ces, state) {
  for (const e of ces) {
    const p = finalPrimary(e);
    if (p === null) {
      out.num(e.p.han * 2 + 1);
    } else {
      out.num((p >= state.p ? (p - state.p) * 2 : (state.p - p) * 2 - 1) * 2);
      state.p = p;
    }
    out.num(paletteIndex.get(st(e)));
  }
}

const streams = {};
// Palette: count, then each pair.
{
  const s = new Stream();
  s.num(palette.length);
  for (const v of palette) s.num(v);
  streams.palette = s;
}
// Canonical combining classes: runs of code points with the same rank (gap, length - 1, rank).
{
  const s = new Stream();
  const sorted = [...classRank.keys()].sort((a, b) => a - b);
  const runs = [];
  for (const cp of sorted) {
    const last = runs[runs.length - 1];
    if (last && last.end + 1 === cp && last.rank === classRank.get(cp)) last.end = cp;
    else runs.push({ start: cp, end: cp, rank: classRank.get(cp) });
  }
  s.num(runs.length);
  let end = -1;
  for (const r of runs) {
    s.num(r.start - end - 1);
    s.num(r.end - r.start);
    s.num(r.rank);
    end = r.end;
  }
  streams.ccc = s;
}
// Canonical decompositions (gap, length, code points).
{
  const s = new Stream();
  const sorted = [...canonical.keys()].sort((a, b) => a - b);
  s.num(sorted.length);
  let previous = -1;
  for (const cp of sorted) {
    s.num(cp - previous - 1);
    const d = canonical.get(cp);
    s.num(d.length);
    for (const x of d) s.num(x);
    previous = cp;
  }
  streams.nfd = s;
}
// Han: runs of code points with the same group (gap, length - 1, group difference).
{
  const s = new Stream();
  const sorted = [...hanGroup.keys()].sort((a, b) => a - b);
  const runs = [];
  for (const cp of sorted) {
    const last = runs[runs.length - 1];
    if (last && last.end + 1 === cp && last.group === hanGroup.get(cp)) last.end = cp;
    else runs.push({ start: cp, end: cp, group: hanGroup.get(cp) });
  }
  s.num(runs.length);
  let end = -1;
  let group = 0;
  for (const r of runs) {
    s.num(r.start - end - 1);
    s.num(r.end - r.start);
    s.signed(r.group - group);
    end = r.end;
    group = r.group;
  }
  streams.han = s;
}
// Single code points: runs (gap, (length - 1) * 2 + kind, then for kind 0 the number of elements
// and the elements every code point of the run has; for kind 1 one element whose primary grows by
// one from a code point to the next).
let singleCount = 0;
{
  const s = new Stream();
  const entries = [...singles.entries()].sort((a, b) => a[0] - b[0]);
  singleCount = entries.length;
  const sameElements = (a, b) => a.length === b.length && a.every((e, i) => finalPrimary(e) === finalPrimary(b[i]) && (finalPrimary(e) !== null || e.p.han === b[i].p.han) && st(e) === st(b[i]));
  const runs = [];
  for (const [cp, ces] of entries) {
    const last = runs[runs.length - 1];
    if (last && last.end + 1 === cp) {
      const lastCes = last.ces;
      const n = last.end - last.start;
      const increments = ces.length === 1 && lastCes.length === 1 && finalPrimary(ces[0]) !== null && finalPrimary(lastCes[0]) !== null &&
        finalPrimary(ces[0]) === finalPrimary(lastCes[0]) + n + 1 && st(ces[0]) === st(lastCes[0]);
      if ((last.kind === 1 || n === 0) && increments && finalPrimary(lastCes[0]) > 0) {
        last.kind = 1;
        last.end = cp;
        continue;
      }
      if (last.kind === 0 && sameElements(ces, lastCes)) {
        last.end = cp;
        continue;
      }
    }
    runs.push({ start: cp, end: cp, kind: 0, ces });
  }
  s.num(runs.length);
  let end = -1;
  const state = { p: 0 };
  for (const r of runs) {
    s.num(r.start - end - 1);
    s.num((r.end - r.start) * 2 + r.kind);
    if (r.kind === 0) s.num(r.ces.length);
    writeElements(s, r.ces, state);
    end = r.end;
  }
  streams.singles = s;
}
// Contractions (number of code points, code points, number of elements, elements), sorted.
let contractionCount = 0;
{
  const s = new Stream();
  const kept = [...contractions].sort((a, b) => {
    for (let i = 0; i < Math.min(a[0].length, b[0].length); i++) if (a[0][i] !== b[0][i]) return a[0][i] - b[0][i];
    return a[0].length - b[0].length;
  });
  contractionCount = kept.length;
  s.num(kept.length);
  const state = { p: 0 };
  for (const [cps, ces] of kept) {
    s.num(cps.length);
    for (const cp of cps) s.num(cp);
    s.num(ces.length);
    writeElements(s, ces, state);
  }
  streams.contractions = s;
}
// Prefixes (number of code points of the prefix, its code points, the code point, number of
// elements, elements).
{
  const s = new Stream();
  const kept = prefixed;
  for (const [, cps] of kept) if (cps.length !== 1) throw new Error('a prefix before a contraction');
  s.num(kept.length);
  const state = { p: 0 };
  for (const [prefix, cps, ces] of kept) {
    s.num(prefix.length);
    for (const cp of prefix) s.num(cp);
    s.num(cps[0]);
    s.num(ces.length);
    writeElements(s, ces, state);
  }
  streams.prefixes = s;
}

const commonSt = secondaryRank.get(common) * 32 + tertiaryRank.get(common);
const out = [];
out.push('// Code generated by tools/gen_collation_table.mjs; DO NOT EDIT.');
out.push('');
out.push('module collation');
out.push('');
out.push(`// ICU's root collation of Node ${process.version} (ICU ${process.versions.icu}, CLDR ${process.versions.cldr}, Unicode ${process.versions.unicode}),`);
out.push(`// from ICU 78.3's FractionalUCA.txt: ${singleCount} code points, ${contractionCount} contractions, ${hanGroup.size} Han characters`);
out.push(`// in ${new Set(hanGroup.values()).size} groups of the radical-stroke order, ${primaryRank.size - 1} explicit primaries, ${secondaryRank.size - 1} secondaries,`);
out.push(`// ${tertiaryRank.size - 1} tertiaries; ${marks.length} combining marks in ${new Set(classRank.values()).size} classes, ${canonical.size} canonical decompositions.`);
out.push('');
out.push(`const han_base = u64(${hanBase})`);
out.push(`const han_group_shift = u64(${hanGroupShift})`);
out.push(`const unassigned_base = u64(${unassignedBase})`);
out.push(`const common_st = u64(${commonSt})`);
for (const [name, s] of Object.entries(streams)) {
  out.push('');
  out.push(`const data_${name} = r'${s.toString()}'`);
}
process.stdout.write(out.join('\n') + '\n');
