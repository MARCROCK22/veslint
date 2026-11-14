// unicorn/text-encoding-identifier-case: `utf8` (or `utf-8` with withDash, in with-dash/, and for
// TextDecoder) and `ascii`, in lower case. The fix is only for the encoding of fs's readFile.
declare const fs: { readFile(path: string, encoding: string, cb?: unknown): void; readFileSync(path: string, encoding: string): string };
declare const args: [string];

const e1 = 'UTF-8';
const e2 = "utf-8";
const e3 = 'UTF8';
const e4 = `Utf8`;
const e5 = 'ASCII';
fs.readFileSync('a.txt', 'UTF-8');
fs.readFile('a.txt', 'Ascii', () => {});
fs.readFile(...args, 'UTF-8');
const d1 = new TextDecoder('UTF8');
const d2 = new TextDecoder('utf8');

// Not reported.
const z1 = 'utf8';
const z2 = 'ascii';
const z3 = 'latin1';
const z4 = String.raw`UTF-8`;
const z5 = `UTF-8${e1}`;
const z6 = '';
