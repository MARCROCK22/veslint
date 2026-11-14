// unicorn/prefer-string-raw: `String.raw` instead of escaping every backslash.
declare const name: string;
declare function expect(value: unknown): { toMatchInlineSnapshot(snapshot: string): void };

const p1 = 'C:\\Windows\\System32';
const p2 = "a\\b";
const p3 = 'it\'s a\\b';
const t1 = `C:\\Users\\${name}\\file`;
function f() {
  return'a\\b';
}

// Not reported.
const z1 = 'a\\';
const z2 = 'a\\b\n';
const z3 = 'a\\`b';
const z4 = 'a\\${b}';
const z5 = 'C:\\Windows';
const z6 = String.raw`a\b`;
const z7 = `a\\b\n`;
const z8 = { 'a\\b': 1 };
type Z9 = 'a\\b';
enum Z10 { A = 'a\\b' }
expect(1).toMatchInlineSnapshot('a\\b');
export { z1 as 'a\\b' };

// 79.0.0: with the types, only where the replacement keeps the type `string`: a `let`, a binding
// annotated `string`, a template with expressions, an argument of type `string`; `as const` is left
// alone. A `String.raw` without backslashes is unnecessary.
let q1 = 'C:\\Windows';
const q2: string = 'a\\b';
const q3 = `a\\b${name}`;
const q4 = 'a\\b' as const;
declare function takes(value: string): void;
takes('a\\b');
const q5 = { key: 'a\\b' };
const r1 = String.raw`abc`;
const r2 = String.raw`it's ${name}`;
const r3 = String.raw`a
b`;
const r4 = String./* keep */raw`abc`;
function r5() {
  return String.raw
  `x` && name;
}
