// unicorn/escape-case: the hexadecimal digits of escapes in one case (upper by default, lower in
// lowercase/), in strings, templates and regular expressions (and `\cX` in patterns).
declare const name: string;
declare function tag(strings: TemplateStringsArray, ...values: unknown[]): string;

const s1 = '\xa9';
const s2 = '\xA9';
const s3 = '\ud834';
const s4 = '\uD834';
const s5 = '\u{1d306}';
const s6 = '\u{1D306}';
const s7 = '\\xa9 \\\xa9';
const t1 = `\xa9${name}\xA9`;
const t2 = tag`\ud834`;
const r1 = /\xa9\ca/;
const r2 = /\xA9\cA/u;

// Not reported.
const z1 = 'xa9';
const z2 = String.raw`\xa9`;
