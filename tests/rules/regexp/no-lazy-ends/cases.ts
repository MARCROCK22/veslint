// Reported (patterns used whole), with suggestions.
export const a1 = /a??/.test('a');
export const a2 = /a*?/.exec('a');
export const a3 = /a+?/.test('a');
export const a4 = /a{3,7}?/.test('a');
export const a5 = 'x'.match(/(?:a|b(c+?))/);
export const a6 = /a(?:c|ab+?)?/.test('a');
const re = /é\d{2,}?/;
export const a7 = re.test('x');
export const a8 = new RegExp('a*?').test('a');
// Not reported: not at the end, greedy, fixed, or not used whole.
export const b1 = /a+?b/.test('a');
export const b2 = /a+/.test('a');
export const b3 = /a{3}?/.test('a');
export const b4 = /a+?/.source;
export const b5 = /a+?/;
