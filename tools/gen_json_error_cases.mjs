// Generates tests/json_error_cases.json for rules/json_errors_test.v: the message of the error
// `JSON.parse(text)` throws in the Node that runs this script (V8), or '' when the text is valid.
// Dev-time only: run `node tools/gen_json_error_cases.mjs` after adding cases.
import fs from 'node:fs';
import path from 'node:path';

const texts = [
  '{}', '[]', '{"a": 1}', ' [1, "x", true, false, null, -1.5e+3, {"b": []}] ', '"s"', '0', '-0.5',
  '', ' ', '{', '[', '{"a"', '{"a":', '{"a": 1', '{"a": 1,', '{"a": 1,}', '[1', '[1,', '[1,]', '[1 2]',
  '{@"typescript-eslint/no-for-in-array": "sometimes"}', '{ @x: 1}', '{\n  @x: 1}', '{\r\n\r\n @x}',
  '{"no-debugger": 2,"no-eval": 1 "no-with": 2}', '{"no-empty": [2,}', '{"a": [2, }', '{a: 1}', "{'a': 1}",
  '{"a" 1}', '{"a": 1 "b": 2}', '{"a": 1, b: 2}', '{"a": undefined}', '{"a": tru}', '{"a": nul', '{"a": truex}',
  '{"a": "x}', '{"a": "x\\q"}', '{"a": "\\u12G4"}', '{"a": "\\u12', '{"a": "a\tb"}', '{"a": "\\"}', '{"a": "ok\\n"}',
  '{"a": -}', '{"a": -x}', '{"a": 01}', '{"a": 1.}', '{"a": 1.x}', '{"a": 1e}', '{"a": 1e+}', '{"a": 1E5}', '{"a": .5}', '{"a": +1}',
  '{} x', '[] []', '1 2', 'x', 'undefined', 'NaN', '[object Object]',
  '{"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaa": @}', '{"a": 1, "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb": @, "c": 2, "dddddddddddddddd": 3}',
  '@{"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaa": 1}', '{"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaa": 1}@', '{"ñññññññññññññññ": @}', '{"a": 1, "b": "ñññññññññññññññññññññ" @}',
  '{"a": [1, {"b": [2, 3}]}', '{"a": {"b": {"c": }}}', '{"a": :}', '{"a": ]}', '{,}', '[,]', '{"a":1}}', ']', '}', ':', ',',
  '{"twenty chars xx": @', '{"twenty-one chars x": @',
];
const cases = texts.map(text => {
  let message = '';
  try { JSON.parse(text); } catch (error) { message = error.message; }
  return { text, message };
});
const file = path.resolve(import.meta.dirname, '../tests/json_error_cases.json');
fs.writeFileSync(file, JSON.stringify({ node: process.version, cases }, null, 1) + '\n');
console.log(`${cases.length} cases, ${cases.filter(c => c.message).length} with an error`);
