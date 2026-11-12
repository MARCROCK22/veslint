// Generates tests/utf8_decode_cases.json: byte sequences (hex) with the text Node decodes from them
// as UTF-8 (hex of its UTF-8), which is what `fs.readFile(path, 'utf8')` gives ESLint. Dev-time only:
// run `node tools/gen_utf8_decode_cases.mjs` when the pinned Node changes. offsets/decode_test.v
// checks offsets.decode_utf8 against it.
import fs from 'node:fs';
import path from 'node:path';

const cases = new Set();
const add = bytes => cases.add(Buffer.from(bytes).toString('hex'));
// Every byte alone, between two letters, and every pair and triple of bytes of each class.
for (let b = 0; b < 256; b++) { add([b]); add([0x61, b, 0x62]); }
const classes = [0x00, 0x41, 0x7f, 0x80, 0x8f, 0x90, 0x9f, 0xa0, 0xbf, 0xc0, 0xc1, 0xc2, 0xdf, 0xe0, 0xe1, 0xec, 0xed, 0xee,
  0xef, 0xf0, 0xf1, 0xf3, 0xf4, 0xf5, 0xf8, 0xfe, 0xff];
for (const a of classes) for (const b of classes) {
  add([a, b]);
  for (const c of classes) add([a, b, c]);
}
// Four bytes: the lead bytes of four-byte sequences with every combination of continuation classes.
const tails = [0x41, 0x80, 0x8f, 0x90, 0xa0, 0xbf, 0xc2, 0xf0];
for (const a of [0xf0, 0xf1, 0xf3, 0xf4, 0xe0, 0xed]) for (const b of tails) for (const c of tails) for (const d of tails) add([a, b, c, d]);
// Texts: valid ones with every length of sequence, a BOM, truncated ends and Latin-1 text.
for (const text of ['', 'plain', 'é€😀', '﻿bom', 'a\u0000b', '�']) add(Buffer.from(text, 'utf8'));
add(Buffer.from('café déjà', 'latin1'));
add([...Buffer.from('😀', 'utf8')].slice(0, 3));
add([0x61, ...Buffer.from('€', 'utf8').slice(0, 2)]);
add([0xff, 0xfe, 0x61, 0x00, 0x62, 0x00]);
add([0xfe, 0xff, 0x00, 0x61, 0x00, 0x62]);
// Random bytes, reproducible.
let seed = 0x2f6e2b1;
const next = () => (seed = (Math.imul(seed, 1103515245) + 12345) >>> 0) >>> 16;
for (let n = 0; n < 400; n++) {
  const bytes = [];
  const length = 1 + (next() % 12);
  for (let i = 0; i < length; i++) bytes.push(next() % 4 === 0 ? next() % 128 : 128 + (next() % 128));
  add(bytes);
}
const out = [...cases].sort().map(hex => {
  const decoded = Buffer.from(hex, 'hex').toString('utf8');
  return [hex, Buffer.from(decoded, 'utf8').toString('hex')];
});
const file = path.resolve(import.meta.dirname, '../tests/utf8_decode_cases.json');
fs.writeFileSync(file, JSON.stringify({ node: process.version, cases: out }) + '\n');
console.log(`${out.length} cases, ${out.filter(([a, b]) => a !== b).length} of them not valid UTF-8, written to ${path.relative(process.cwd(), file)}`);
