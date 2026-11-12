// Generates rules/regexp_property_data.v: the Unicode data rules/regexp_match.v needs to match,
// like V8 (the engine ESLint runs on), a regular expression in the `u` mode:
// - the code points of every `\p{…}` that rules/regexp_unicode.v lists as valid;
// - which code points are the same one when case is ignored (`(?i:…)`).
// Node runs this script at development time only; veslint never runs Node. Everything is asked
// to V8 itself, with no table of Unicode in between: a property is matched against every code
// point, and a code point is in a case class if the class of all the others matches it.
//
// Usage: node tools/gen_regexp_properties.mjs > rules/regexp_property_data.v && v fmt -w rules/regexp_property_data.v
import fs from 'node:fs';
import path from 'node:path';

const root = path.join(import.meta.dirname, '..');
const names = fs.readFileSync(path.join(root, 'rules/regexp_unicode.v'), 'utf8');

// The strings of a `const name = [...]` of rules/regexp_unicode.v.
function nameList(name) {
  const match = names.match(new RegExp(`const ${name} = \\[([^\\]]*)\\]`));
  if (!match) {
    throw new Error(`rules/regexp_unicode.v: ${name} not found`);
  }
  return [...match[1].matchAll(/'([^']*)'/g)].map(m => m[1]);
}

const lastCodePoint = 0x10ffff;
// Every code point in order, in two strings: a surrogate next to another would be read as a pair.
const belowSurrogates = codePointString(0, 0xd7ff);
const aboveSurrogates = codePointString(0xe000, lastCodePoint);

function codePointString(first, last) {
  const parts = [];
  for (let start = first; start <= last; start += 0x1000) {
    const chunk = [];
    for (let cp = start; cp < start + 0x1000 && cp <= last; cp++) {
      chunk.push(cp);
    }
    parts.push(String.fromCodePoint(...chunk));
  }
  return parts.join('');
}

// The code points that `source` (one character of a pattern) matches with the `u` flag, as
// inclusive [first, last] pairs.
function matchedRanges(source) {
  const ranges = [];
  const push = (first, last) => {
    const previous = ranges.at(-1);
    if (previous && previous[1] === first - 1) {
      previous[1] = last;
    } else {
      ranges.push([first, last]);
    }
  };
  const run = new RegExp(`(?:${source})+`, 'gu');
  for (const match of belowSurrogates.matchAll(run)) {
    push(match.index, match.index + match[0].length - 1);
  }
  const one = new RegExp(`^(?:${source})$`, 'u');
  for (let cp = 0xd800; cp <= 0xdfff; cp++) {
    if (one.test(String.fromCharCode(cp))) {
      push(cp, cp);
    }
  }
  for (const match of aboveSurrogates.matchAll(run)) {
    // The index is in UTF-16 units: one for each of the first 0x2000 code points, then two.
    const first = match.index <= 0x1fff ? 0xe000 + match.index : 0x10000 + (match.index - 0x2000) / 2;
    push(first, first + [...match[0]].length - 1);
  }
  return ranges;
}

// The sets, each with the keys that give it: `gc=Lu`, `sc=Latin`, `scx=Latn` and, for a binary
// property, its name. Names that are aliases share a set.
const sets = new Map();
function addSet(key, source) {
  const ranges = matchedRanges(source);
  const id = ranges.flat().join(',');
  if (!sets.has(id)) {
    sets.set(id, { keys: [], ranges });
  }
  sets.get(id).keys.push(key);
}
for (const value of nameList('regexp_gc_values')) {
  addSet(`gc=${value}`, `\\p{gc=${value}}`);
}
for (const value of nameList('regexp_script_values')) {
  addSet(`sc=${value}`, `\\p{sc=${value}}`);
}
for (const value of nameList('regexp_script_extensions_values')) {
  addSet(`scx=${value}`, `\\p{scx=${value}}`);
}
for (const name of nameList('regexp_binary_properties')) {
  addSet(name, `\\p{${name}}`);
}

// Checks of what rules/regexp_match.v assumes.
function rangesOf(key) {
  for (const set of sets.values()) {
    if (set.keys.includes(key)) {
      return set.ranges;
    }
  }
  throw new Error(`no set for ${key}`);
}
if (rangesOf('Any').flat().join() !== `0,${lastCodePoint}`) {
  throw new Error('\\p{Any} is not every code point');
}
if (rangesOf('gc=L').flat().join() !== matchedRanges('\\p{L}').flat().join()) {
  throw new Error('\\p{L} is not General_Category=L');
}
if (rangesOf('gc=Lu').flat().join() !== matchedRanges('\\p{General_Category=Uppercase_Letter}').flat().join()) {
  throw new Error('gc and General_Category differ');
}
for (let cp = 0; cp <= lastCodePoint; cp += 97) {
  const inSet = rangesOf('scx=Grek').some(([first, last]) => cp >= first && cp <= last);
  if (inSet !== /^\p{Script_Extensions=Greek}$/u.test(String.fromCodePoint(cp))) {
    throw new Error(`Script_Extensions=Greek differs at U+${cp.toString(16)}`);
  }
}

// A set is written as the gaps and the lengths of its ranges: for each range, the code points
// skipped since the previous one and its length minus one, each number in groups of five bits
// from the lowest, one character per group; the sixth bit says that another group follows.
const alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
function encodeNumber(value) {
  let out = '';
  do {
    const group = value % 32;
    value = Math.floor(value / 32);
    out += alphabet[group + (value > 0 ? 32 : 0)];
  } while (value > 0);
  return out;
}
function encodeRanges(ranges) {
  let out = '';
  let next = 0;
  for (const [first, last] of ranges) {
    out += encodeNumber(first - next) + encodeNumber(last - first);
    next = last + 1;
  }
  return out;
}

// The case classes: the code points that the `i` flag makes equal to another one. A code point
// has a partner if the class of all the other code points matches it.
const escape = cp => `\\u{${cp.toString(16)}}`;
const withPartner = [];
for (let cp = 0; cp <= lastCodePoint; cp++) {
  const others = [];
  if (cp > 0) {
    others.push(cp === 1 ? escape(0) : `${escape(0)}-${escape(cp - 1)}`);
  }
  if (cp < lastCodePoint) {
    others.push(cp === lastCodePoint - 1 ? escape(lastCodePoint) : `${escape(cp + 1)}-${escape(lastCodePoint)}`);
  }
  if (new RegExp(`^[${others.join('')}]$`, 'iu').test(String.fromCodePoint(cp))) {
    withPartner.push(cp);
  }
}
const partners = String.fromCodePoint(...withPartner);
const classOf = new Map();
for (const cp of withPartner) {
  const matched = source => [...partners.matchAll(new RegExp(source, 'gu'))].map(m => m[0].codePointAt(0));
  const members = matched(`(?i:${escape(cp)})`);
  // A character, a class and the flag itself must all give the same class.
  const inClass = matched(`(?i:[${escape(cp)}])`);
  const withFlag = [...partners.matchAll(new RegExp(escape(cp), 'giu'))].map(m => m[0].codePointAt(0));
  if (members.join() !== inClass.join() || members.join() !== withFlag.join()) {
    throw new Error(`the case class of U+${cp.toString(16)} depends on how it is written`);
  }
  if (members.length < 2 || !members.includes(cp)) {
    throw new Error(`U+${cp.toString(16)} has no case class`);
  }
  classOf.set(cp, members);
}
// The classes must be an equivalence: every member has the same class.
const folds = [];
for (const cp of withPartner) {
  const members = classOf.get(cp);
  for (const member of members) {
    if (classOf.get(member).join() !== members.join()) {
      throw new Error(`the case class of U+${cp.toString(16)} is not the one of U+${member.toString(16)}`);
    }
  }
  if (members[0] !== cp) {
    folds.push(cp, members[0]);
  }
}

const quoted = values => `[${values.map(v => `'${v}'`).join(', ')}]`;
const all = [...sets.values()];
const out = [
  '// Code generated by tools/gen_regexp_properties.mjs; DO NOT EDIT.',
  '',
  'module rules',
  '',
  `// Unicode data to match the regular expressions of Node ${process.version} (V8 ${process.versions.v8}, ICU ${process.versions.icu}, Unicode ${process.versions.unicode}).`,
  '',
  '// The keys of each set of regexp_property_sets, separated by spaces: `gc=Lu` for a value of',
  '// General_Category, `sc=Latin` for one of Script, `scx=Latn` for one of Script_Extensions, and',
  '// the name of a binary property.',
  `const regexp_property_keys = ${quoted(all.map(set => set.keys.join(' ')))}`,
  '',
  '// The code points of each set: for each of its ranges, in order, the code points skipped since',
  '// the previous one and its length minus one. A number is written in groups of five bits from the',
  '// lowest, one character of regexp_property_alphabet per group; the sixth bit says that another',
  '// group follows.',
  `const regexp_property_sets = ${quoted(all.map(set => encodeRanges(set.ranges)))}`,
  '',
  `const regexp_property_alphabet = '${alphabet}'`,
  '',
  '// The code points that are equal to another one when case is ignored, as pairs: the code point',
  '// and the lowest code point of its class (which is not listed). Sorted by the first.',
  `const regexp_case_folds = [${folds.map(n => `u32(0x${n.toString(16)})`).join(', ')}]`,
  '',
];
process.stdout.write(out.join('\n'));
