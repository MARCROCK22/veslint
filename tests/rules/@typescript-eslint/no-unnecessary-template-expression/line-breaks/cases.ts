// The report starts two units before the expression: its line and its column are counted with
// a lone CR, U+2028, U+2029 and CRLF as line breaks (see no-floating-promises/line-breaks).
declare const text: string;
const a = `${text}`;const b = `${text}`; const c = `${text}`; const d = `${text}`;
const e = `${text}`;
const f = `${  text }`; const g = `${'😀'}`; const h = `${text}`;
// The two units before the expression may be a line break, or the `{` of the line before.
const f1 = `${text}`; const f2 = `${
text}`; const f3 = `${  text}`; const f4 = `${  text}`;
const i = `a${'b'} c${'d'} ${'e'}`;
// A literal that ends in white space is allowed before each line break.
const j = `a${' '}b${' '} c${' '} d${' '}
e${' '}f`;
export { a, b, c, d, e, f, f1, f2, f3, f4, g, h, i, j };
