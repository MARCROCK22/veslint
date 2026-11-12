/* global Number:off, parseInt:off, String:off, BigInt:off */
/* global parseFloat:off, isNaN:off, isNaN:writable, 1:off, __proto__:off */
/* global undefined:off, NaN: off, Infinity :off */
// A global a comment turns off is not a variable of the global scope any more, so a constant
// that uses it is not evaluated; unless a lib of the project declares the name (as a type or as a
// value), which typescript-eslint's scope always has.
declare const list: number[];
// Declared by the lib (es2022): still evaluated.
list.filter(x => x > 1)[Number('0')];
list.filter(x => x > 1)[String(0) as unknown as number];
list.filter(x => x > 1)[BigInt(0) as unknown as number];
list.filter(x => x > 1).at(Number('0'));
// Not in any lib: gone.
list.filter(x => x > 1)[parseInt('0')];
list.filter(x => x > 1)[parseFloat('0')];
list.filter(x => x > 1).at(NaN);
list.filter(x => x > 1).at(undefined);
list.filter(x => x > 1).at(1 / Infinity);
// The last value of a name counts.
list.filter(x => x > 1).at(isNaN(1) ? 5 : 0);
/* global parseFloat */
// A later comment gives the global back to the whole file.
list.filter(x => x > 1)[parseFloat('0.0')];
