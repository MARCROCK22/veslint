// unicorn/prefer-set-size: `Set#size` instead of the length of the spread set.
declare const values: number[];

const s1 = [...new Set(values)].length;
const s2 = Array.from(new Set(values)).length;
const s3 = [...new Set(/* keep */ values)].length;
function f() {
  return[...new Set(values)].length;
}

// 79.0.0: a `const` of a Set, an annotated Set, a Set by its type.
const set = new Set(values);
const y1 = [...set].length;
declare const readonlySet: ReadonlySet<number>;
const y2 = Array.from(readonlySet).length;
function y3(s: Set<string>) { return [...s].length; }
const y4 = [...(set as Set<number>)].length;
const y5 = new ([...set].length as any)();
[...set].length = 1;
function y6() {
  values
  return [...set].length
}

// Not reported.
const z2 = [...new Map()].length;
const z3 = [...new Set(values)]?.length;
const z4 = [...new Set(values), 1].length;
