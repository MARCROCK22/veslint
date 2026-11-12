// Line breaks other than LF. ESLint and TypeScript also end a line at U+2028, at U+2029, at a
// lone CR and at CRLF, wherever they are, and count the columns from there; tree-sitter's rows
// only count LF. This file has those characters for real: in comments, in code, in strings and in
// template literals. Every statement ends with `;`.
declare function task(): Promise<number>;
declare function tag(strings: TemplateStringsArray, ...values: unknown[]): Promise<void>;
// A line comment ends at U+2028, task();
// at U+2029, task();
// at a lone CR,task();
// and at CRLF.
task();
/* A block comment with U+2028 , U+2029 , a lone CR and CRLF
 in it. */ task();
// In code, after a `;`: U+2028, U+2029, a lone CR, CRLF, two lone CRs, and LF and a lone CR.
task(); task(); task();task();
task();task();
task();
// Between the tokens of a statement, and with characters of two UTF-16 units before a report.
task ( ).finally
(() => {}); task();
/* 😀 */ task(); /* 😀😀 */ task(); /* ñ — 😀 */ task();/* 😀 */ /* 😀 */ task();
// In strings: U+2028 and U+2029 as they are, and a line continuation with each line break.
const s1 = 'a b c'; task();
const s2 = "a\b\
c\ d\ e\
f"; task();
// In template literals, in their text and around their substitutions.
const t1 = `a b cd
e`; task();
const t2 = `${s1}${s2} ${t1} `; task();
tag`${t2} `;tag`\`; tag` `;
// In a function, with indentation after each line break.
async function inside(): Promise<void> {  task();     task(); 	task();
  await task();}void inside;