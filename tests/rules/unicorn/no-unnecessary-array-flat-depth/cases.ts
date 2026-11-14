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
