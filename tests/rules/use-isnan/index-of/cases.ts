// use-isnan with enforceForIndexOf: indexOf and lastIndexOf of NaN.
declare const list: number[];
declare const strings: string[];
declare function sideEffect(): number;

list.indexOf(NaN);
list.lastIndexOf(NaN);
list.indexOf(Number.NaN);
list['indexOf'](NaN);
list[`lastIndexOf`](NaN);
list?.indexOf(NaN);
(list.indexOf)(NaN);
list.indexOf((NaN));
list.indexOf(NaN, 1);
list.indexOf((sideEffect(), NaN));
strings.indexOf(NaN as unknown as string);
list.indexOf(NaN, 1, 2);
list.indexOf(...[NaN]);
list.includes(NaN);
list.findIndex(Number.isNaN);
list.indexOf<number>(NaN);
indexOf(NaN);
declare function indexOf(value: number): number;

// A `NaN` or a `Number` that is not the global is not NaN (10.15.0).
function shadowNaN(NaN: number, arr: number[]) {
  return arr.indexOf(NaN);
}
function shadowNumber(Number: { NaN: number }, arr: number[]) {
  return arr.lastIndexOf(Number.NaN);
}
