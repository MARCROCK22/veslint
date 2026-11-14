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

// 79.0.0: no template of any tag is checked; the raw text of a template is its source text.
declare function tagged(strings: TemplateStringsArray, ...values: unknown[]): string;
const y1 = tagged`\xa9`;
const y2 = tagged`\u{00b1} ${1} \xa9`;
const y3 = `\xa9
\xa9 ${1} \ud834`;
