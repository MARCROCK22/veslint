declare const foo: any;
declare const arr: number[];
declare const maybe: number[] | undefined;
declare const cond: boolean;
declare function f(x: unknown): void;

// Reported.
arr.map(function () {});
arr.map(function foo() { f(1); });
arr.filter((x) => { f(x); });
arr.every(x => { if (x) { return true; } });
arr.some(function (x) { if (x) return; return true; });
arr.find(x => { return; });
arr.findLast(x => { f(x); });
arr.findIndex(x => { f(x); });
arr.findLastIndex(x => { f(x); });
arr.flatMap(x => { f(x); });
arr.reduce((acc, x) => { f(acc + x); });
arr.reduceRight((acc, x) => { f(acc + x); }, 0);
arr.sort((a, b) => { f(a - b); });
arr.toSorted((a, b) => { f(a - b); });
arr['map'](x => { f(x); });
arr[`filter`](x => { f(x); });
maybe?.map(x => { f(x); });
(maybe?.filter)!(x => { f(x); });
Array.from(arr, x => { f(x); });
Uint8Array.from(arr, function (x) { f(x); });
Array.fromAsync(arr, async x => { f(x); });
arr.map(cond ? x => { f(x); } : x => x);
arr.map(cond || function () {});
arr.map((function () { return function () {}; })());
arr.map(async function () {});
arr.map(x => { switch (x) { case 1: return 1; default: f(x); } });
arr.map(x => { try { return 1; } catch { f(x); } });
class C {
  m() { return arr.map(function named() {}); }
}

// Not reported.
arr.map(x => x);
arr.map(function* () {});
arr.map(x => { return x; });
arr.map(x => { throw x; });
arr.map(x => { while (true) {} });
arr.forEach(x => { f(x); });
arr.forEach(x => x);
arr.forEach(x => { return x; });
arr.reduce(x => { if (x) return 1; else return 2; });
foo.map(f);
arr.map(f);
arr.map(cond && (x => { f(x); }));
arr.notAMethod(x => { f(x); });
arr.map(x => { f(x); }, 1)[0];
Array.from(arr, 0, x => { f(x); });
Array.of(x => { f(x); });
arr.filter(async x => { f(x); });
new Array().map(x => { f(x); });

export { C };
