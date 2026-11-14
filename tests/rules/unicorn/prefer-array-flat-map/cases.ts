// unicorn/prefer-array-flat-map: `.flatMap()` instead of `.map().flat()`.
declare const list: number[];
declare const React: { Children: { map(a: unknown, f: unknown): number[][] } };

const m1 = list.map(x => [x, x]).flat();
const m2 = list.map(x => [x]).flat(1);
const m3 = (list.map(x => [x])).flat();
const m4 = list?.map(x => [x]).flat();
const m5 = list
  .map(x => [x])
  .flat();

// Not reported.
const z1 = list.map(x => [x]).flat(2);
const z2 = list.map(x => [x])?.flat();
const z3 = list.map(x => [x]).flat?.();
const z4 = React.Children.map(list, x => [x]).flat();
const z5 = list.map(x => [x]).flat(1.0);
