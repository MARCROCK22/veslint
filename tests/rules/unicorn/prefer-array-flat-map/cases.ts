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

// 79.0.0: a callback with side effects gets a suggestion; no fix with type arguments or comments;
// `.filter(…).flatMap(…)`; a receiver known not to be an array is left alone.
declare const words: string[];
declare function log(x: unknown): void;
const m1 = words.map(w => [w, w]).flat();
const m2 = words.map(w => { log(w); return w; }).flat();
const m3 = words.map(w => w.length).flat();
const m4 = words.map<string[]>(w => [w]).flat();
const m5 = words.map(w => [w]) /* keep */ .flat();
declare const wordSet: Set<string> & { map(f: (w: string) => string[]): { flat(): string[] } };
const m6 = wordSet.map(w => [w]).flat();
const m7 = words.filter(w => w.length > 1).flatMap(w => [w, w]);
const m8 = words.filter(w => w ? 1 : 0).flatMap(w => [w, 1]);
const m9 = words.filter(w => w).flatMap(w => [w]);
const m10 = words.filter(w => w /* keep */).flatMap(w => [w, w]);
