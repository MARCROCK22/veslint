// unicorn/prefer-set-size: `Set#size` instead of the length of the spread set.
declare const values: number[];

const s1 = [...new Set(values)].length;
const s2 = Array.from(new Set(values)).length;
const s3 = [...new Set(/* keep */ values)].length;
function f() {
  return[...new Set(values)].length;
}

// Not reported: a variable is not a set for typescript-eslint's definitions.
const set = new Set(values);
const z1 = [...set].length;
const z2 = [...new Map()].length;
const z3 = [...new Set(values)]?.length;
const z4 = [...new Set(values), 1].length;
