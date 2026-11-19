// Reported: control characters written as themselves or with \x or \u, with a suggestion when they
// have an escape of their own.
export const a1 = /\x00/;
export const a2 = /\x0C/;
export const a3 = /\x1F/;
export const a4 = /\u000a/;
export const a5 = /\u{0a}/u;
export const a6 = /[\x01-\x1f]/;
export const a7 = new RegExp('\x0c');
export const a8 = new RegExp('\\x1b');
export const a9 = RegExp('\u0000');
export const a10 = new RegExp('é' + '\\u0009');
export const a11 = /	/;
// Not reported: the escapes of their own, characters that are not control characters.
export const b1 = /\0/;
export const b2 = /\t\n\v\f\r/;
export const b3 = new RegExp('\t');
export const b4 = new RegExp('\\t');
export const b5 = /\x20/;
export const b6 = /\cJ/;
