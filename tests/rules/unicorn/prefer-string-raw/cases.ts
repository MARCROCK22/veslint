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
