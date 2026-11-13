// Generates tests/regexp_match_cases.json for jsregexp/regexp_match_test.v: for each pattern and
// text, whether `new RegExp(pattern, 'u').test(text)` is true in the Node that runs this script
// (V8). Dev-time only: run `node tools/gen_regexp_match_cases.mjs` after adding cases.
import { execFileSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';

const cases = [
  ['^[a-z]+(_[a-z]+)+$', ['snake_case', 'snake', 'snake_', '_snake', 'a_b_c', 'A_b', 'a__b']],
  ['^no default$', ['no default', 'No default', ' no default', 'no default ', 'no  default']],
  ['abc', ['abc', 'xabcx', 'ab', 'acb', '']],
  ['', ['', 'a']],
  ['a|b|', ['a', 'b', 'c', '']],
  ['^(?:a|ab)(?:c|bcd)(?:d*)$', ['abcd', 'acd', 'abc', 'abbcd']],
  ['a*', ['', 'aaa', 'b']],
  ['^a+$', ['', 'a', 'aaaa', 'aab']],
  ['^a?b$', ['b', 'ab', 'aab']],
  ['^a{2}$', ['a', 'aa', 'aaa']],
  ['^a{2,}$', ['a', 'aa', 'aaaaa']],
  ['^a{1,3}$', ['', 'a', 'aaa', 'aaaa']],
  ['^a{0}$', ['', 'a']],
  ['^(a+?)(a*)$', ['aaa']],
  ['^a+?$', ['aaa', 'aab']],
  ['^.$', ['a', '\n', '\r', ' ', ' ', '\u{1F600}', 'ab', '']],
  ['^[^]$', ['a', '\n', '']],
  ['^[]$', ['', 'a']],
  ['^[abc]+$', ['abcabc', 'abd']],
  ['^[^abc]+$', ['xyz', 'xay', '']],
  ['^[a-c0-2_-]+$', ['a1_-', 'd', 'b2']],
  ['^[\\d\\s]+$', ['1 2\t3', '1a']],
  ['^[\\D]+$', ['abc', 'a1']],
  ['^[\\w-]+$', ['a-b_C9', 'a b']],
  ['^[\\W]+$', [' -!', 'a']],
  ['^[\\S]+$', ['ab', 'a b']],
  ['^[\\b]$', ['\b', 'b']],
  ['^[a\\-z]$', ['-', 'b', 'a', 'z']],
  ['^\\d+$', ['0123456789', '١٢٣', '12a']],
  ['^\\w+$', ['aZ_09', 'ñ', 'a-b']],
  ['^\\s+$', [' \t\n\v\f\r        　﻿', '​', 'a']],
  ['\\bfoo\\b', ['foo', 'a foo b', 'foobar', 'afoo', 'foo-bar', 'ñfoo']],
  ['\\Boo\\B', ['foo', 'foot', 'oo']],
  ['^\\$\\^\\.\\*\\+\\?\\(\\)\\[\\]\\{\\}\\|\\\\\\/$', ['$^.*+?()[]{}|\\/', 'x']],
  ['^\\x41\\u0042\\u{43}\\u{1F600}\\uD83D\\uDE00$', ['ABC\u{1F600}\u{1F600}', 'ABC']],
  ['^\\cJ\\t\\n\\v\\f\\r\\0$', ['\n\t\n\v\f\r\0', 'x']],
  ['^(a)(b)?\\2\\1$', ['aba', 'aa', 'abba', 'ab']],
  ['^(?<x>a|b)\\k<x>$', ['aa', 'bb', 'ab']],
  ['^\\k<x>(?<x>a)$', ['a', 'aa']],
  ['^(?:(?<x>a)|(?<x>b))\\k<x>$', ['aa', 'bb', 'ab', 'ba']],
  ['^(?:(a)|b)*\\1$', ['aba', 'ab', 'aa', 'b', 'aab']],
  ['^(a*)*$', ['', 'aaa', 'b']],
  ['^(a*)+$', ['', 'aaa']],
  ['^(?:a?){3}$', ['', 'aa', 'aaaa']],
  ['^(a|ab)(c|bcd)$', ['abcd', 'ac']],
  ['a(?=b)', ['ab', 'ac', 'a']],
  ['a(?!b)', ['ab', 'ac', 'a']],
  ['(?<=a)b', ['ab', 'cb', 'b']],
  ['(?<!a)b', ['ab', 'cb', 'b']],
  ['^(?=(a+))a*b\\1$', ['aaabaaa', 'aaabaa', 'aba']],
  ['(?<=(\\d+)(\\d+))$', ['1053']],
  ['(?<=\\1(a))b', ['aab', 'ab']],
  ['(?<=([abc])\\1)d', ['aad', 'abd']],
  ['^(?!.*__)[a-z_]+$', ['a_b', 'a__b']],
  ['^(?:(?=a)\\w|\\d)+$', ['a1a', 'b1']],
  ['^[\\u{1F600}-\\u{1F64F}]$', ['\u{1F600}', '\u{1F650}', 'a']],
  ['^\\u{1F600}+$', ['\u{1F600}\u{1F600}', '\u{1F600}a']],
  ['^.{2}$', ['\u{1F600}a', '\u{1F600}', 'ab']],
  ['^(a+)+b$', ['aaaaaaaaaaaaaaaaaaaab', 'aaaab']],
  ['^(?:x|y)*?z$', ['xyxz', 'z', 'xw']],
  ['^a{2,3}?a$', ['aaa', 'aaaa', 'aa', 'aaaaa']],
  ['^[a-z]+(?:[A-Z][a-z]*)*$', ['camelCase', 'PascalCase', 'snake_case']],
  ['^(?:[^\\x00-\\x7F]|[a-z])+$', ['añb', 'aNb']],
  ['é|ñ', ['señor', 'cafe']],
  ['^[.]$', ['.', 'a']],
  ['^a.c$', ['abc', 'a\nc', 'ac']],
  ['x*$', ['abc', 'abxx']],
  ['^$', ['', ' ']],
  ['^(|a)+$', ['a', 'aa', '']],
  ['^(a|)*b$', ['aab', 'b']],
  ['^(?:a|b)+?c', ['abac', 'c']],
  ['[a-z]{3}\\d{2,}', ['abc12', 'ab123', 'xabc1234']],
  // Unicode property escapes.
  ['^\\p{L}+$', ['abc', 'ñandú', '日本', 'a1', '', 'Ωmega', '\u{10400}']],
  ['^\\p{Lu}\\p{Ll}+$', ['Émile', 'émile', 'ÉMILE', 'Ab', '\u{10400}\u{10428}']],
  ['^\\P{L}+$', ['123', '1a', ' -', 'é']],
  ['^[\\p{L}\\p{N}_]+$', ['año_2024', 'a-b', '٣x', 'Ⅷ']],
  ['^[^\\p{Lu}]+$', ['abc', 'aBc', '123', 'É']],
  ['^[\\P{Lu}]+$', ['abc', 'aBc', '123']],
  ['^[^\\P{Lu}]+$', ['ABC', 'aBc', 'ÉÑ']],
  ['^\\p{Script=Greek}+$', ['αβγ', 'abc', 'Ωμέγα', 'µ']],
  ['^\\p{sc=Grek}+$', ['αβγ', 'abc']],
  ['^\\p{scx=Hira}+$', ['ひらがな', 'ー', 'カ', 'a']],
  ['^\\p{Script_Extensions=Latin}+$', ['abc', 'ñ', 'α', '1']],
  ['^\\p{General_Category=Decimal_Number}+$', ['123', '١٢٣', 'x', '½']],
  ['^\\p{gc=Nd}+$', ['123', '١٢٣', 'x']],
  ['^\\p{Nd}{2,3}$', ['1', '12', '١٢٣', '1234']],
  ['^\\p{Alphabetic}+$', ['abcñ', 'a1', 'ⅷ']],
  ['^\\p{Uppercase}+$', ['ABC', 'aB', 'Ⅷ', 'É']],
  ['^\\p{Lowercase}+$', ['abc', 'aB', 'ⅷ', 'ª']],
  ['^\\p{White_Space}+$', [' \t\n\u00a0\u2003', '\u200b', 'a']],
  ['^\\p{Emoji}+$', ['\u{1F600}', '1', 'a', '#']],
  ['^\\p{Emoji_Presentation}+$', ['\u{1F600}', '1', '\u2764']],
  ['^\\p{ASCII}+$', ['abc~', 'ñ', '\x7f']],
  ['^\\p{Any}+$', ['a\n\u{10FFFF}', '']],
  ['^\\p{Assigned}+$', ['a', '\u0378', '\ue000']],
  ['^\\p{Cn}+$', ['\u0378', 'a']],
  ['^\\p{Co}+$', ['\ue000', '\u{100000}', 'a']],
  ['^\\p{ID_Start}\\p{ID_Continue}*$', ['año1', '1a', '_a', 'a_b', 'ℂ']],
  ['^\\p{XID_Start}+$', ['ab', '1']],
  ['^\\p{AHex}+$', ['09afAF', 'g', 'ＡＦ']],
  ['^\\p{Hex_Digit}+$', ['09afAF', 'g', 'ＡＦ']],
  ['^\\p{Lu}[\\p{L}\\p{N}]*$', ['Émile2', 'émile', 'É_x', 'Ω']],
  ['\\p{Sc}\\p{Nd}+', ['cost $12', '€5', '$x']],
  ['^\\p{Lt}$', ['ǅ', 'Ǆ', 'ǆ']],
  ['^\\P{Any}$', ['a', '']],
  // The flags of a modifier.
  ['(?i:abc)', ['ABC', 'aBc', 'abd', 'xAbCx']],
  ['^(?i:a)b$', ['Ab', 'AB', 'ab']],
  ['^a(?-i:b)$', ['ab', 'aB']],
  ['^(?i:a(?-i:b)c)$', ['AbC', 'ABC', 'abc', 'abC']],
  ['^(?i:a)b(?i:c)$', ['AbC', 'ABC', 'abc']],
  ['^(?i:[a-z]+)$', ['ABC', 'aBc', 'ab1', 'ſ', '\u212a', 'é']],
  ['^(?i:[^a-z]+)$', ['ABC', '123', 'ſ', '\u212a', 'É']],
  ['^(?i:[k-s]+)$', ['\u212a', 'ſ', 'Q', 'T']],
  ['^(?i:[\\u{212A}])$', ['k', 'K', '\u212a', 'j']],
  ['^(?i:[^k])$', ['\u212a', 'K', 'k', 'x']],
  ['^(?i:\\w+)$', ['ſ', '\u212a', 'é', 'aZ_9']],
  ['^\\w+$', ['ſ', '\u212a']],
  ['^(?i:\\W+)$', ['ſ', '\u212a', ' -', 'é']],
  ['(?i:\\bfoo\\b)', ['ſfoo', 'FOO', 'a Foo b', 'foo\u212a', 'éfoo']],
  ['(?i:\\Boo\\B)', ['ſoo\u212a', 'FOOT', 'oo']],
  ['\\bfoo\\b', ['ſfoo', 'foo\u212a']],
  ['^(?i:\\p{Lu}+)$', ['abc', 'ABC', '123', 'ǅ']],
  ['^(?i:\\P{Lu}+)$', ['ABC', 'abc', '123']],
  ['^(?i:[^\\P{Lu}]+)$', ['A', 'a', '1']],
  ['^(?i:[^\\p{Lu}]+)$', ['a', 'A', '1']],
  ['^(?i:\\p{Ll}+)$', ['ABC', 'ǅ', '1', 'ª']],
  ['^(?i:ß)$', ['ß', 'ẞ', 'SS', 'ss']],
  ['(?i:straße)', ['STRASSE', 'STRAßE', 'STRAẞE']],
  ['^(?i:σ+)$', ['Σ', 'ς', 'σ', 'Σσς', 's']],
  ['^(?i:ı)$', ['I', 'i', 'ı', 'İ']],
  ['^(?i:i)$', ['I', 'i', 'ı', 'İ']],
  ['^(?i:k)$', ['K', '\u212a', 'k']],
  ['^(?i:å)$', ['Å', '\u212b', 'a']],
  ['^(?i:ǆ)$', ['Ǆ', 'ǅ', 'ǆ', 'DŽ']],
  ['^(?i:\\u{10400})$', ['\u{10428}', '\u{10400}', '\u{10401}']],
  ['^(?i:\\u{13A0})$', ['\u{AB70}', '\u{13A0}', '\u{13A1}']],
  ['^(?i:ΜΙΚΡΌ)$', ['μικρό', 'µικρό', 'μικρο']],
  ['^(?i:\\d+)$', ['123', '١']],
  ['^(?i:\\s+)$', [' \t', 's']],
  ['^(?i:.)$', ['A', '\n', '\u212a']],
  ['^(?i:[a-c]{2,})$', ['AbC', 'A', 'abD']],
  ['^(?i:a|b)+$', ['AbBa', 'abc']],
  ['^(?i:(a)\\1)$', ['aA', 'Aa', 'ab', 'AA']],
  ['^(a)(?i:\\1)$', ['aA', 'aa', 'AA']],
  ['^(?i:(a))\\1$', ['Aa', 'AA', 'aa', 'aA']],
  ['^(?i:(?<x>ſ)\\k<x>)$', ['ſS', 'sſ', 'ss', 'sx']],
  ['^(?i:(\\u212a)\\1\\1)$', ['kK\u212a', '\u212akk', 'kkj']],
  ['(?<=(?i:a))b', ['Ab', 'ab', 'cb']],
  ['(?i:(?<=\\1(a)))b', ['aAb', 'Aab', 'ab']],
  ['(?<!(?i:[a-z]))1', ['A1', '_1', 'ſ1']],
  ['^(?s:.)$', ['\n', 'a', '\u2028']],
  ['^(?-s:.)$', ['\n', 'a']],
  ['^(?s:a.b)c.$', ['a\nbcx', 'a\nbc\n', 'axbcx']],
  ['^(?s:[^]).$', ['\na', '\n\n']],
  ['(?m:^b$)', ['a\nb\nc', 'ab', 'a\rb', 'a\u2028b\u2029', 'b']],
  ['(?m:^)b', ['a\nb', 'ab', 'b']],
  ['a(?m:$)', ['a\nb', 'ab', 'a']],
  ['^b', ['a\nb', 'b']],
  ['a$', ['a\nb', 'a']],
  ['(?m:^$)', ['a\n\nb', 'ab', '', 'a\n']],
  ['(?m:^)$', ['a\n', 'a', '']],
  ['(?im-s:^a.c$)', ['x\nABC', 'A\nC', 'x\nabcd']],
  ['(?is:a.c)', ['A\nC', 'abc', 'ac']],
  ['(?ims:^A.c$)', ['x\na\nC\ny', 'x\nabcd']],
  ['(?i-m:^a$)', ['A', 'x\na']],
  ['(?m-i:^a$)', ['x\na', 'x\nA']],
  ['^(?i:id|url|html)$', ['ID', 'Url', 'HTML', 'idx']],
  ['(?i:(?m:^x)y)', ['a\nXY', 'aXY']],
  ['(?m:a(?-m:$))', ['a\nb', 'a']],
  ['(?i:a(?i:b)(?-i:c)d)', ['ABcD', 'ABCD']],
  // V8 decides the letters `\\w` and `\\W` get when case is ignored, and whether a class in brackets
  // ignores case, with the flags of the last group that was opened, also after it is closed.
  ['(?i:x)|\\w', ['ſ', '\u212a', 's', '-']],
  ['(?i:x)|[\\w]', ['ſ', '-']],
  ['(?i:x)|\\W', ['ſ', '-', 's']],
  ['(?i:x)|[^\\w]', ['ſ', '-']],
  ['(?i:x)|[\\W]', ['ſ', '-']],
  ['(?i:x)|a\\bſ', ['aſ']],
  ['(?i:x)|a\\Bſ', ['aſ']],
  ['(?i:x)?\\w', ['ſ']],
  ['(?i:)\\w', ['ſ']],
  ['\\w(?i:x)?', ['ſ']],
  ['(?i:x)|(?-i:\\w)', ['ſ']],
  ['(?-i:(?i:x)|\\w)', ['ſ']],
  ['(?i-s:x)|\\w', ['ſ']],
  ['(?s-i:x)|\\w', ['ſ']],
  ['(?i:x)|(?:\\w)', ['ſ']],
  ['(?i:x)|(\\w)', ['ſ']],
  ['(?i:x)|(?=\\w)', ['ſ']],
  ['(?i:x)|(?=)\\w', ['ſ']],
  ['(?i:x)|(?<=)\\w', ['ſ']],
  ['(?i:x)|(?!y)\\w', ['ſ']],
  ['(?i:x)|(?<n>y)?\\w', ['ſ']],
  ['(?i:x)|(?i:y)|\\w', ['ſ']],
  ['(?i:x)(?-i:y)|\\w', ['ſ']],
  ['(?-i:y)|(?i:x)|\\w', ['ſ']],
  ['(?i:x(?:y))?\\w', ['ſ']],
  ['(?i:x)?(y)?\\w', ['ſ']],
  ['(?i:x)?y?\\w', ['ſ']],
  ['(?i:(?-i:x)|\\W)', ['s', 'S', 'k', 'ſ', '\u212a', 'a', '-']],
  ['(?i:(?-i:x)|[^\\w])', ['s', 'ſ', '-']],
  ['(?i:(?-i:x)|[\\W])', ['s', 'ſ', '-', 'a']],
  ['(?i:(?-i:x)|\\w)', ['ſ', 's', '-']],
  ['(?i:(?-i:x)|a\\bſ)', ['aſ']],
  ['(?s:x)|.', ['\n']],
  ['(?m:x)|^b', ['a\nb']],
  ['(?s:(?-s:y)|.)', ['\n']],
  ['(?m:(?-m:x)|^b)', ['a\nb']],
  ['(?i:(x))\\1', ['xX', 'XX']],
  ...['a', 's', 'ſ', '\\u212a', 'ß', '\\p{Lu}', '\\P{Lu}', '\\p{Ll}', '\\d', '\\D', '\\w', '\\W', '.', '[a]', '[^a]', '[ß]', '[sx]', '[a-z]', '[^a-z]',
    '[\\w]', '[^\\w]', '[\\W]', '[^\\W]', '[\\Wa]', '[\\wé]', '[ſ]', '[^ſ]', '[\\p{Lu}]', '[^\\p{Lu}]', '[\\P{Lu}]', '(a)\\1?', '[a]{1}', '[\\x61]'].flatMap(atom =>
    [['^(?i:(?-i:x)|', ')$'], ['^(?:(?i:x)|', ')$'], ['^(?i:(?-i:x)?', ')$'], ['^(?i:(q)?', ')$'], ['^(?i:(?-i:x)?(?s:y)?', ')$'], ['^(?i:(?-i:x)|(?:', '))$'], ['^(?i:(?-i:(?i:x))?', ')$']].map(([before, after]) =>
      [before + atom + after, ['a', 'A', 's', 'S', 'ſ', '\u212a', 'k', 'ß', 'ẞ', '-', '1']])),
];

// Patterns and texts made from a few atoms, in an order that depends only on the seed: what the
// cases above do not think of.
let seed = 20261010;
function random(count) {
  seed = (Math.imul(seed, 1103515245) + 12345) >>> 0;
  return (seed >>> 8) % count;
}
const pick = list => list[random(list.length)];
const letters = ['a', 'B', 'k', 'K', 's', 'S', 'ſ', '\u212a', 'ß', 'ẞ', 'σ', 'Σ', 'ς', 'é', 'É', 'ǅ', '1', '_', ' ', '\n'];
const atoms = [
  ...letters.map(c => (c === '\n' ? '\\n' : c)),
  '.', '\\w', '\\W', '\\d', '\\D', '\\s', '\\S', '\\b', '\\B', '^', '$',
  '\\p{L}', '\\P{L}', '\\p{Lu}', '\\P{Lu}', '\\p{Ll}', '\\p{Lt}', '\\p{Nd}', '\\p{Script=Greek}', '\\p{Alphabetic}',
  '[a-k]', '[^s-z]', '[K-S]', '[\\p{Lu}\\d]', '[^\\P{Ll}_]', '[\\wé]', '[^\\W\\d]', '[σß]', '[^ſ]', '[\\s\\S]',
];
function randomTerm(depth) {
  let term;
  const kind = random(10);
  if (depth < 2 && kind === 0) {
    term = `(?:${randomPattern(depth + 1)})`;
  } else if (depth < 2 && kind === 1) {
    term = `(${randomPattern(depth + 1)})`;
  } else if (depth < 2 && kind <= 4) {
    const flags = pick(['i', 'i', 'i', 's', 'm', 'im', 'is', 'ims', '-i', 'i-s', 'm-i', 's-m', '-ims']);
    term = `(?${flags}:${randomPattern(depth + 1)})`;
  } else if (depth < 2 && kind === 5) {
    term = `(${pick(['?=', '?!', '?<=', '?<!'])}${randomPattern(depth + 1)})`;
    return term;
  } else {
    term = pick(atoms);
    if (['^', '$', '\\b', '\\B'].includes(term)) {
      return term;
    }
  }
  return term + pick(['', '', '', '', '?', '*', '+', '{1,2}', '*?', '+?']);
}
function randomPattern(depth) {
  const alternatives = [];
  for (let i = 0, n = 1 + (random(4) === 0 ? 1 : 0); i < n; i++) {
    let alternative = '';
    for (let j = 0, m = 1 + random(depth === 0 ? 3 : 2); j < m; j++) {
      alternative += randomTerm(depth);
    }
    alternatives.push(alternative);
  }
  return alternatives.join('|');
}
function randomText() {
  let text = '';
  for (let i = 0, n = random(6); i < n; i++) {
    text += pick(letters);
  }
  return text;
}
const randomCases = [];
while (randomCases.length < 600) {
  let pattern = randomPattern(0);
  if (random(3) === 0) {
    pattern = `^(?:${pattern})$`;
  }
  // Half of them with a backreference to the first group.
  if (pattern.includes('(') && random(2) === 0) {
    pattern += pick(['\\1', '(?i:\\1)']);
  }
  try {
    new RegExp(pattern, 'u');
  } catch {
    continue;
  }
  if (pattern.length > 90) {
    continue;
  }
  randomCases.push([pattern, Array.from({ length: 4 }, randomText)]);
}
cases.push(...randomCases);
// V8 14.6 does not always give the same answer to a pattern with the `i` flag in a modifier: with
// its optimizations it misses some matches (`/(?i:\\p{Lu}S)/u` does not match `sſ`, which
// `/\\p{Lu}S/iu` does), and without them it misses others (`/(?m:(?im:s+))+?/u` does not match
// `S`). It stops optimizing by itself once a process has generated much regexp code. Only the
// cases that V8 answers the same both ways are kept, each batch of patterns in two new
// processes: jsregexp/regexp_match.v follows the specification there.
const worker = `
const optimized = process.execArgv.includes('--regexp-optimization');
const cases = JSON.parse(require('node:fs').readFileSync(0, 'utf8'));
const answers = cases.map(([pattern, texts]) => {
  const re = new RegExp(pattern, 'u');
  return texts.map(text => re.test(text));
});
if (new RegExp('(?m:(?im:s+))+?', 'u').test('S') !== optimized) {
  throw new Error('V8 does not optimize regular expressions as asked');
}
process.stdout.write(JSON.stringify(answers));
`;
function answersOf(batch, flag) {
  return JSON.parse(execFileSync(process.execPath, [flag, '-e', worker], { input: JSON.stringify(batch), maxBuffer: 1 << 26 }));
}
const out = [];
let dropped = 0;
for (let start = 0; start < cases.length; start += 100) {
  const batch = cases.slice(start, start + 100);
  const optimized = answersOf(batch, '--regexp-optimization');
  const plain = answersOf(batch, '--no-regexp-optimization');
  batch.forEach(([pattern, texts], i) => {
    texts.forEach((text, j) => {
      if (optimized[i][j] === plain[i][j]) {
        out.push({ pattern, text, matches: optimized[i][j] });
      } else {
        dropped++;
      }
    });
  });
}
// Patterns V8 rejects.
const invalid = ['(', 'a{2,1}', '\\k<x>', '[b-a]', '\\1', '(?<x>a)(?<x>b)', '\\-', 'a**', '{', '\\p{Foo}', '\\p{Script=Foo}', '\\p{Latin}', '\\p', '(?ii:a)', '(?i-i:a)', '(?-:a)', '(?x:a)', '\\p{RGI_Emoji}', '[\\p{L}-z]'];
for (const pattern of invalid) {
  let threw = false;
  try { new RegExp(pattern, 'u'); } catch { threw = true; }
  if (!threw) throw new Error(`V8 accepts /${pattern}/u`);
}
const file = path.resolve(import.meta.dirname, '../tests/regexp_match_cases.json');
fs.writeFileSync(file, JSON.stringify({ node: process.version, cases: out, invalid }) + '\n');
console.log(`${out.length} cases, ${out.filter(c => c.matches).length} matching, ${dropped} dropped (V8 answers them two ways), ${invalid.length} invalid`);
