// unicorn/no-for-each: `for…of` instead of `.forEach()`.
declare const list: number[];
declare const maybe: number[] | undefined;
declare function use(x: unknown): void;
declare function get(): number[];

list.forEach(x => use(x));
list.forEach((x, i) => {
  use(x + i);
});
list.forEach(function (x) {
  if (x > 1) return;
  use(x);
});
list.forEach(x => {
  if (x) return use(x);
  use(x);
});
maybe?.forEach(x => use(x));
get()?.forEach(x => use(x));
list.forEach(x => { x = x + 1; use(x); });
list.forEach(({ length }) => use(length));
const done = () => list.forEach(x => use(x));
list.forEach((x) => {
  return { x };
});

// Reported, not fixed.
const r1 = list.forEach(x => use(x));
list.forEach(use);
list.forEach(async x => use(x));
list.forEach((x: number) => use(x));
list.forEach(x => {
  for (const y of list) {
    return;
  }
});
list.forEach(function (x) { use(this); });
list.forEach(x => use(x), list);
const x = 1;
list.forEach(y => use(x + y));
list.forEach(x => use(x));

// Not reported.
declare const React: { Children: { forEach(a: unknown, f: unknown): void } };
React.Children.forEach(list, (x: number) => use(x));

// 79.0.0: only known arrays are fixed; receivers known not to be arrays are left (with TypeScript's
// types `React?.Children` of a declared React, which the upstream test without a program
// reports); class bodies; optional chains in a statement position.
declare function bar(x: unknown): void;
React?.Children.forEach(bar);
declare const unknownThing: any;
unknownThing.forEach((x: unknown) => bar(x));
declare const known: number[];
known.forEach(x => bar(x));
known.forEach(x => class {});
known.forEach(x => function () {});
known.forEach(x => ({}));
known.forEach(/* keep */ x => bar(x));
known.forEach(x => { if (x) return; bar(x); });
known.forEach(x => { if (x) return bar(x); });
declare const maybeKnown: number[] | undefined;
if (maybeKnown) maybeKnown?.forEach(x => bar(x));
maybeKnown?.forEach(x => bar(x));
const knownSet = new Set([1]);
knownSet.forEach(x => bar(x));
