// unicorn/no-unnecessary-array-flat-depth: `.flat(1)`.
declare const nested: number[][];

const f1 = nested.flat(1);
const f2 = nested?.flat(1);
const f3 = nested.flat(1,);
const f4 = nested.flat((1));

// Not reported.
const z1 = nested.flat();
const z2 = nested.flat(2);
const z3 = nested.flat?.(1);
const z4 = nested.flat(1.5);

// 79.0.0: the whole argument list goes, but the comments; a receiver known not to be an array is
// left alone.
const g1 = nested.flat(
  1,
);
const g2 = nested.flat(/* keep */ 1);
const g3 = nested.flat(1 // keep
);
declare const notArray: Set<number> & { flat(depth: number): void };
notArray.flat(1);
