// use-isnan with its default options: comparisons and switches, not indexOf.
declare const x: number;
declare const list: number[];
declare function sideEffect(): number;

// Comparisons with NaN and Number.NaN: an equality gets suggestions.
if (x === NaN) {}
if (NaN === x) {}
if (x == NaN) {}
if (x !== NaN) {}
if (x != Number.NaN) {}
if (x < NaN) {}
if (x >= Number.NaN) {}
if ((x) === (NaN)) {}
if (x === Number['NaN']) {}
if (x === Number?.NaN) {}
if (x + 1 === NaN) {}
if ((sideEffect(), x) === NaN) {}
if (x === (sideEffect(), NaN)) {}
const flag = list[0] !== NaN ? 'number' : 'NaN';

// NaN behind TypeScript's wrappers is not an Identifier: nothing.
if (x === (NaN as number)) {}
if (x === Number.NaN!) {}
if (x === <number>NaN) {}
if (x === globalThis.NaN) {}
if (x === Number.isNaN) {}
if (Number.isNaN(x)) {}

// switch (NaN) and case NaN.
switch (NaN) {
  case 1:
    break;
}
switch (x) {
  case NaN:
    break;
  case Number.NaN:
    break;
  case (sideEffect(), NaN):
    break;
  default:
    break;
}

// indexOf is not checked by default.
list.indexOf(NaN);
list.lastIndexOf(Number.NaN);
