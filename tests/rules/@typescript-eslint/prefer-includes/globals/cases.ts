// The static values of builtin globals, with `/* global */` comments on them.
/* global String, RegExp:off, Number:writable */
declare const text: string;
text.indexOf(String('a')) !== -1;
new RegExp('abc').test(text);
RegExp('abc').test(text);
/a/.test(text);
new RegExp(String(Number('1'))).test(text);
