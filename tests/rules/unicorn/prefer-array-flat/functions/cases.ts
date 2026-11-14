// unicorn/prefer-array-flat with functions: ['flattenDeep', 'utils.flat'].
declare const nested: number[][];
declare function flattenDeep(a: unknown): number[];
declare const utils: { flat(a: unknown): number[] };

const f1 = flattenDeep(nested);
const f2 = utils.flat(nested);

// Not reported.
const z1 = flattenDeep(nested, 1);
