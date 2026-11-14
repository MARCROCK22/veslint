// unicorn/no-array-for-each: `for…of` instead of `.forEach()`.
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
