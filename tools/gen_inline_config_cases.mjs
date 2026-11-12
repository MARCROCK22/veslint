// Generates tests/inline_config_cases.json for rules/directives_test.v: what ESLint's own parser of
// configuration comments (ConfigCommentParser.parseJSONLikeConfig of @eslint/plugin-kit, which reads
// the text with levn and, when that fails, as JSON) makes of the text of a `/* eslint … */` comment:
// the rules and their values, or the message of its error. A value JSON does not have (undefined,
// NaN, a regular expression or a date, which levn reads) is written as {"$js": "…"}.
// Dev-time only: run `node tools/gen_inline_config_cases.mjs` after adding cases.
import fs from 'node:fs';
import path from 'node:path';
import { createRequire } from 'node:module';

const root = path.resolve(import.meta.dirname, '..');
const require = createRequire(path.join(root, 'build/eval/spider-byte/node_modules/eslint/package.json'));
const { ConfigCommentParser } = require('@eslint/plugin-kit');
const parser = new ConfigCommentParser();

const texts = [
  // JSON, and the relaxed notation of levn.
  'a: 2', 'a: "error"', "a: 'warn'", 'a: off', 'a: [2]', 'a: ["error", {"b": true}]', 'a: [2, {b: true, c: [1, 2], d: {e: null}}]', 'a: 2, b: 1', '"a": 2, \'b\': 1',
  'a:2,b:[1,"x"]', '  a :  2  ', 'a: [ 2 , { b : "c d" , e : f } ]', 'a/b: 2, @c/d-e: [1, x]', 'a: [2, x y]', 'a: [2, x, y]', 'a: [2, "x, y"]', 'a: [2, \'it\\\'s\']',
  'a: [2, "q\\"q"]', 'a: [2, "\\n\\t\\r\\b\\f\\\\"]', 'a: [2, "\\u0041\\u00e9\\ud83d\\ude00"]', 'a: [2, "\\x41\\q\\u12"]', 'a: [2, "tab\there"]', "a: [2, 'a\"b']", 'a: [2, "a\'b"]',
  'a: [2, 1.5, -1, 0, 1e3, .5, 5., 0x10, 0b11, 0o17, +3, -0, 1_000, 12abc, 1.2.3, Infinity, -Infinity]', 'a: [2, true, false, null, True, NULL]', 'a: [2, [], {}, [[]], [{}], {b: {}}]',
  'a: [2, {b: 1,}]', 'a: [2, 1,]', 'a: [2,, 1]', 'a: [2, {b: 1 c: 2}]', 'a: [2, {"b": 1, "b": 2, c: 3}]', 'a: [2, {10: 1, 2: 2, b: 3}]', 'a: [2, {b: [1, {c: [2, {d: 3}]}]}]',
  'a: [2, {__proto__: 1, b: 2}]', 'a: [2, {"__proto__": 1}]', '__proto__: 2, a: 1', 'a: [2, {b: x:y}]', 'a: [2, {b: "x:y"}]', 'a: [2, b:c]', 'a: [2, {b}]', 'a: [2, {b:}]',
  'a: [2, key: value]', 'a: [2, {b: [x y, z]}]', 'a: [2, "a" "b"]', 'a: [2, "a"b]', 'a: [2, a"b"]', 'a: [2, "unterminated]', "a: [2, 'unterminated]", 'a: [2, (1, 2)]', 'a: [2, (x)]',
  // Values JSON does not have.
  'a: [2, undefined]', 'a: [2, NaN]', 'a: [2, /x/]', 'a: [2, /x/gi]', 'a: [2, /x/u]', 'a: [2, /(/]', 'a: [2, #2020-01-02#]', 'a: [2, #nope#]', 'a: [2, {b: undefined}]', 'a: undefined',
  // Severities that are not valid, texts levn does not take: the text is then read as JSON, with
  // the names before a colon in quotes.
  'a: sometimes', 'a: "sometimes"', 'a: [3]', 'a: []', 'a: 2 b: 1', 'a: 2 b: 1 c: 0', 'a: [2,', 'a: [2', 'a: {b: 1}', 'a: ERROR', 'a: [ERROR]', 'a: 2, b: nope', 'a', 'a:', ': 2', '',
  ' ', ',', 'a: 2,', ', a: 2', 'a: 2,, b: 1', 'a: [2]]', 'a: [2}}', 'a: [2, {b: 1}', '@"x/y": "sometimes"', 'a: 3, "b": [2, {"c": 1}]', '"a": [3, {"b": [1, 2]}] "c": 2',
  'a: "x" b: 2', 'a-b/c: nope, d: 2', 'a: 2.5', 'a: -1', 'a: "2"', 'a: 02', 'a: [02]', 'a: 2e0', 'a: [1.0]', 'a: 0x2', 'a: true', 'a: null', 'a: [null]', 'a: [[2]]',
];

// The values as JSON: `undefined` is not a key of an object for JSON.stringify, so it is written.
function plain(value) {
  if (value === undefined) return { $js: 'undefined' };
  if (typeof value === 'number' && !Number.isFinite(value)) return { $js: String(value) };
  if (value instanceof RegExp) return { $js: String(value) };
  if (value instanceof Date) return { $js: `date ${value.toISOString()}` };
  if (Array.isArray(value)) return value.map(plain);
  if (value && typeof value === 'object') {
    const keys = [];
    for (const key in value) keys.push(key);
    return { $keys: keys.map(key => [key, plain(value[key]), Object.hasOwn(value, key)]) };
  }
  return value;
}
const cases = texts.map(text => {
  const result = parser.parseJSONLikeConfig(text);
  return result.ok ? { text, rules: plain(result.config).$keys } : { text, error: result.error.message };
});
const file = path.join(root, 'tests/inline_config_cases.json');
fs.writeFileSync(file, `{"cases":[\n${cases.map(c => JSON.stringify(c)).join(',\n')}\n]}\n`);
console.log(`${cases.length} texts, ${cases.filter(c => c.error).length} that ESLint cannot read`);
