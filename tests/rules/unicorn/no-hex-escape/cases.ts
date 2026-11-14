// unicorn/no-hex-escape: `\u00XX` instead of `\xXX`, in strings, templates and regular expressions.
declare const name: string;
declare function tag(strings: TemplateStringsArray, ...values: unknown[]): string;

const s1 = '\x1B';
const s2 = "a\x41b";
const s3 = '\\x41';
const s4 = '\\\x41';
const t1 = `\x1B${name}\x1b`;
const t2 = tag`\x1B`;
const r1 = /\x1B/;
const r2 = /[\x00-\x7F]/u;

// Not reported.
const z1 = '\u001B';
const z2 = 'x41';
const z3 = String.raw`\x1B`;
const z4 = /\\x41/;
