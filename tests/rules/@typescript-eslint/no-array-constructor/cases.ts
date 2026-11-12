// Reported: not one argument, the callee is `Array`, no type arguments.
declare const x: number, y: number, z: number, args: number[], more: number[];
new Array();
new Array;
Array();
new Array(1, 2);
Array(1, 2);
new Array(x, y, z);
Array(x, y, z);
Array?.();
Array?.(0, 1);
(Array)(1, 2);
new (Array)(1, 2);
new Array(
  1, // one
  2,
);
Array(/* empty */);
Array(...args, ...more);
new Array(...args, ...more);
new Array // no parentheses
;
const nested = Array(Array(1, 2), new Array());
const commented = Array /* callee */ (1, 2);
const spaced = new Array ( 3 , 4 ) ;
Array(1, 2);
new Array(1, 2)[0];

// Not reported.
new Array<number>(1, 2);
Array<number>(1, 2);
new Array<string>();
new Array(1);
Array(1);
Array(x);
Array(...args);
new foo.Array();
foo.Array(1, 2);
Array.of(1, 2);
Array`tagged`;
new Array2();
declare const foo: { Array: ArrayConstructor };
