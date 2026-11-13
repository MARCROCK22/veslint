// Generates tests/package_pattern_cases.json for rules/package_pattern_test.v: for the `package` of a
// type specifier, the regular expression typescript-eslint makes of it
// (typeDeclaredInDeclarationFile of type-utils: `new RegExp(`${packageName}|${typesPackageName}`)`)
// and, for each of the texts, whether it matches in the Node that runs this script (V8); or that V8
// rejects the pattern. The packages are names as they are written, names with the characters that
// mean something in a regular expression, and patterns made at random out of what V8 reads its own
// way outside the `u` mode. Dev-time only: run `node tools/gen_package_pattern_cases.mjs` after
// adding cases.
import { execFileSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';

// The names TypeScript gives the files of packages, and other texts for the patterns.
const texts = [
  'fake-pkg/index.d.ts', 'fake.pkg/index.d.ts', '@scope/pkg/dist/index.d.ts', '@types/node/fs.d.ts', '@types/scope__pkg/index.d.ts',
  'scope__pkg/index.d.ts', 'lodash.merge/index.d.ts', 'lodashXmerge/index.d.ts', 'socket.io/dist/index.d.ts', 'a/b.d.ts', 'aa/x', 'aaa', 'ab', 'b',
  'x+y/index.d.ts', 'xxy/index.d.ts', 'weird (pkg)/index.d.ts', 'Pkg/Index.d.ts', 'pkg/index.d.ts', 'emoji-\u{1F600}/index.d.ts', '\u{1F600}',
  'a{2}/x', 'a{/x', 'a{2/x', '{2}', 'a\\b/x', '[x]/y', 'x]', 'u{2}', 'uu', 'u0041', 'A', 'k', 'k<n>', 'x', 'x1', 'x12', 'c', '\\c', '\\cA', '\\',
  '\n', 'a\nb', '\t', '\u0001', '\u0008', '\u000a', '\u0011', '\u001f', '\u00ff', '\u0100', '8', '9', '18', '\u00018', '1', '12', '0', '-', ']', '^', '$', '|', '',
  'ſ', 'S', 's', 'ß', 'SS', 'é', 'É', 'K', '\u212a', 'p{L}', 'pL', 'P', 'word boundary', 'line\u2028sep', ' ', '_', 'a-z', 'q', 'aXb', 'ABC', 'abc',
];

const packages = [
  // Names of packages.
  'fake-pkg', 'fake.pkg', 'ake-pk', '@scope/pkg', '@scope/other', 'scope__pkg', '@types/node', 'node', 'lodash.merge', 'socket.io', 'x+y', 'x', '',
  '@scope', '@/pkg', '@a/b/c', 'Pkg', 'pkg', 'emoji-\u{1F600}', '\u{1F600}', 'weird (pkg)', 'a/b', '~tilde', 'under_score', 'dash-', '.', '..',
  '@types/scope__pkg', 'index.d.ts', 'fake-pkg/index', '/', '@',
  // Characters that mean something in a regular expression.
  'a*', 'a+', 'a?', 'x+', 'a{2}', 'a{2,}', 'a{2,3}', 'a{', 'a{2', 'a{,2}', 'a{2,1}', '{2}', '{', '}', ']', 'x]', 'a{}', 'a{2}{3}', 'a{a}', '(a)', '(a', 'a)', '(?:a)|b',
  '[x]', '[^x]', '[]', '[^]', '[a-z]+', '[z-a]', '[\\d-x]', '[x-\\d]', '[\\d-a-z]', '[\\w-]', '[a-]', '[-a]', '[\\b]', '[\\c1]', '[\\c_]', '[\\cA]', '[\\c]',
  '[\\1]', '[\\8]', '[\\18]', '[\\k]', '[\\x4]', '[\\u00]', '[\\-]', '[\\B]', '[', '[a', '\\', 'a\\',
  '^fake', 'pkg$', '^$', 'a|b', '|', 'a||b', '^', '$', '\\$', '\\.', 'fake\\.pkg', '\\/', '\\-',
  '\\d', '\\D', '\\w+', '\\W', '\\s', '\\S', '\\b', '\\B', 'word\\b', '\\bx', '\\n', '\\t', '\\v', '\\f', '\\r', '\\0', '\\00', '\\012', '\\0123', '\\377', '\\400',
  '\\1', '\\8', '\\9', '\\18', '\\81', '\\12', '\\123', '(a)\\1', '(a)\\2', '(a)\\12', '(a)(b)\\2\\1', '(a)\\18', '(?:a)\\1', '\\1(a)', '(a\\1)', '(a)|\\1',
  '\\k', '\\k<n>', '(?<n>a)\\k<n>', '(?<n>a)\\k', '\\k<n>(?<n>a)', '(?<n>a)|(?<n>b)', '(?<n>a)(?<n>b)', '(?<n>.)\\k<n>',
  '\\x41', '\\x4', '\\x', '\\xg1', '\\u0041', '\\u004', '\\u', '\\u{41}', '\\u{2}', '\\ud83d\\ude00', '\\ud83d', '\\p{L}', '\\P{L}', '\\p', '\\pL',
  '\\cA', '\\ca', '\\c', '\\c1', '\\c_', '\\ck', '\\a', '\\e', '\\z', '\\ ', '\\\\', '\\[x\\]', '\\{2\\}',
  '(?=a)', '(?!a)', '(?=a)*', '(?=a){2}', '(?!a)+b', '(?<=a)b', '(?<!a)b', '(?<=a)*', '(?<=\\/)x', 'a(?=\\/)', '.(?!.)', '(?<!.).',
  '.', '.*', '.+?', '^.$', '^..$', 'a.c', '[^]', '\\s\\S', '^[\\s\\S]*$',
  '(?i:pkg)', '(?i:PKG)', '(?i:s)', '(?i:ſ)', '(?i:ß)', '(?i:k)', '(?i:é)', '(?i:[a-c])', '(?i:[^a-c])', '(?i:\\w)', '(?-i:a)', '(?i:a(?-i:b)c)', '(?i:(a)\\1)',
  '(?s:.)', '(?m:^b)', '(?m:a$)', '(?s-m:^.$)', '(?ims:a)', '(?x:a)', '(?i', '(?i:', '(?:', '(?', '(?<', '(?<n', '(?<n>', '*', '+', '?', 'a**', 'a+*', 'a??', 'a*?', 'a+?b',
  '(a|b)*c', '(a*)*', '(a*)+b', '(?:a?){3}', '(a|ab)(c|bcd)', '^(a+)+$', 'x{0}', 'x{0,0}y', 'x{1,2}?', 'a{1}{', 'a{1}}',
  // An astral character is two units for these patterns. (A surrogate without its pair is only
  // written as an escape: the JSON reader of V does not take one.)
  '\u{1F600}', '[\u{1F600}]', '[^\\ud83d]', '\\ude00', '.\\ude00', '^.{2}$', '^[^]$',
];

// Patterns made from a few atoms, in an order that depends only on the seed.
let seed = 20261013;
function random(count) {
  seed = (Math.imul(seed, 1103515245) + 12345) >>> 0;
  return (seed >>> 8) % count;
}
const pick = list => list[random(list.length)];
const atoms = ['a', 'b', 'x', 'k', '/', '-', '.', '@', '_', '1', '8', '{', '}', ']', '{2}', '{1,}', '{,1}', '\\1', '\\2', '\\8', '\\0', '\\07', '\\k', '\\c', '\\cA', '\\x4', '\\x41',
  '\\u', '\\u0061', '\\u{2}', '\\p', '\\d', '\\w', '\\W', '\\s', '\\b', '\\B', '\\/', '\\.', '^', '$', '[a-x]', '[^/]', '[\\d-x]', '[\\c1]', '[\\8]', '[]', '[^]',
  '[\\w.]', '(a)', '(?:b)', '(?=a)', '(?!x)', '(?<=a)', '(?<!/)', '(?<n>a)', '\\k<n>', '(?s:.)', '(?m:^)', '\u{1F600}', '\\ud83d'];
const quantifiers = ['', '', '', '', '*', '+', '?', '{2}', '{1,2}', '{0,}', '*?', '+?', '{'];
while (packages.length < 620) {
  let pattern = '';
  for (let i = 0, n = 1 + random(4); i < n; i++) {
    pattern += pick(atoms) + pick(quantifiers);
    if (random(6) === 0) pattern += '|';
  }
  if (!packages.includes(pattern) && pattern.length <= 40) {
    packages.push(pattern);
  }
}

// typeDeclaredInDeclarationFile of @typescript-eslint/type-utils.
const patternOf = packageName => `${packageName}|${packageName.replace(/^@([^/]+)\//, '$1__')}`;

// V8 does not always give the same answer to a pattern with the `i` flag in a modifier (see
// tools/gen_regexp_match_cases.mjs): each batch is answered by two new processes, with and without
// V8's optimizations, and an answer that is not the same in both is left out (`?`).
const worker = `
const { patterns, texts } = JSON.parse(require('node:fs').readFileSync(0, 'utf8'));
process.stdout.write(JSON.stringify(patterns.map(pattern => {
  let re;
  try { re = new RegExp(pattern); } catch { return null; }
  return texts.map(text => (re.test(text) ? '1' : '0')).join('');
})));
`;
function answersOf(patterns, flag) {
  return JSON.parse(execFileSync(process.execPath, [flag, '-e', worker], { input: JSON.stringify({ patterns, texts }), maxBuffer: 1 << 26 }));
}
const cases = [];
let dropped = 0;
for (let start = 0; start < packages.length; start += 100) {
  const batch = packages.slice(start, start + 100);
  const patterns = batch.map(patternOf);
  const optimized = answersOf(patterns, '--regexp-optimization');
  const plain = answersOf(patterns, '--no-regexp-optimization');
  batch.forEach((packageName, i) => {
    if (optimized[i] === null) {
      cases.push({ package: packageName, pattern: patterns[i], error: true });
      return;
    }
    const matches = [...optimized[i]].map((answer, j) => (answer === plain[i][j] ? answer : '?')).join('');
    dropped += [...matches].filter(answer => answer === '?').length;
    cases.push({ package: packageName, pattern: patterns[i], matches });
  });
}
const file = path.resolve(import.meta.dirname, '../tests/package_pattern_cases.json');
fs.writeFileSync(file, `{"node":${JSON.stringify(process.version)},"texts":${JSON.stringify(texts)},"cases":[\n${cases.map(c => JSON.stringify(c)).join(',\n')}\n]}\n`);
const valid = cases.filter(c => !c.error);
console.log(`${cases.length} packages (${cases.length - valid.length} that V8 rejects) on ${texts.length} texts: ${valid.length * texts.length - dropped} answers, ${dropped} left out (V8 answers them two ways)`);
