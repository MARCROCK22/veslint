/* global parseFloat */
declare const list: number[];
// Turned off by the configuration.
list.filter(x => x > 1)[parseInt('0')];
// Turned off by the configuration; the comment above gives it back.
list.filter(x => x > 1)[parseFloat('0')];
// Not a global of ecmaVersion 2019, and the lib of this folder (es5) does not declare it.
list.filter(x => x > 1)[BigInt(0) as unknown as number];
// Declared by the lib: the configuration cannot take it away.
list.filter(x => x > 1)[Number('0')];
// Read-only in the configuration.
list.filter(x => x > 1)[isNaN(1) ? 1 : 0];
