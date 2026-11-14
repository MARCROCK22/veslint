// unicorn/prefer-array-some: `.some()` instead of `.find()`, `.findIndex()` and `.filter().length`.
declare const list: number[];

if (list.find(x => x > 1)) {}
const s1 = !list.findLast(x => x > 1);
const s2 = Boolean(list.find(x => x > 1));
const s3 = list.find(x => x > 1) ? 1 : 2;
const s4 = list.find(x => x > 1) !== undefined;
const s5 = list.find(x => x > 1) == null;
const s6 = (list.find(x => x > 1)) === undefined;
const s7 = list.findIndex(x => x > 1) !== -1;
const s8 = list.findLastIndex(x => x > 1) === -1;
const s9 = list.findIndex(x => x > 1) >= 0;
const s10 = list.findIndex(x => x > 1) < 0;
const s11 = list.filter(x => x > 1).length > 0;
const s12 = (list.filter(x => x > 1)).length !== 0;
while (list.find(x => x) && list.length) {}

// Not reported.
const z1 = list.find(x => x > 1);
const z2 = undefined !== list.find(x => x > 1);
const z3 = list.findIndex(x => x > 1) !== 0;
const z4 = list.filter(x => x > 1).length >= 1;
const z5 = list.filter(undefined).length > 0;
const z6 = list.find(x => x) ?? 1;

// eslint-plugin-unicorn 79.0.0: results kept in a `const` only read as booleans.
declare const predicate: (value: number) => boolean;
declare const receiver: object;
declare const unknownValues: { find(predicate: unknown): unknown; filter(predicate: unknown): unknown[] };
declare const typed: Uint8Array;
declare const anyValues: any;
function v1() {
  const found = list.find(predicate);
  if (found) {}
  return !found;
}
function v2() {
  const found = typed.findLast(predicate, receiver);
  return Boolean(found) || !found;
}
function v3() {
  const found = unknownValues.find(predicate);
  return Boolean(found);
}
function v4() {
  const found = anyValues.find(predicate);
  return Boolean(found);
}
function v5() {
  // Not reported: `!found` needs an indexed collection receiver.
  const found = unknownValues.find(predicate);
  return !found;
}
function v6() {
  // Not reported: used for its value, annotated, or `let`.
  const found = list.find(predicate);
  const annotated: number | undefined = list.find(predicate);
  let reassignable = list.find(predicate);
  return [found, Boolean(annotated), Boolean(reassignable)];
}

// Known non-indexed collections and type arguments are skipped.
declare const set: Set<number> & { find(predicate: unknown): unknown; findIndex(predicate: unknown): number; filter(predicate: unknown): unknown[] };
declare const generic: { find<T>(predicate: unknown): T };
if (set.find(predicate)) {}
const n1 = set.findIndex(predicate) !== -1;
const n2 = set.filter(predicate).length > 0;
if (generic.find<number>(predicate)) {}
declare const $items: number[];
const n3 = $items.filter(x => x > 1).length > 0;

// Comments in what the fix removes.
const c1 = list.find(predicate) /* keep */ === undefined;
const c2 = list.findIndex(predicate) !== /* keep */ -1;
const c3 = list.findIndex(predicate) // keep
  !== -1;
const c4 = list.findIndex(predicate) /* kept */ !== -1;
const c5 = list.filter(x => x > 1).length /* keep */ > 0;
const c6 = list.filter(x => x > 1) /* keep */ .length > 0;

// `.findLastIndex()` and `.filter()` with callbacks that may have side effects are suggestions.
declare function log(value: number): boolean;
let count = 0;
const e1 = list.findLastIndex(predicate) !== -1;
const e2 = list.findLastIndex(value => log(value)) === -1;
const e3 = list.findLastIndex(value => value > 1) === -1;
const e4 = list.filter(predicate).length > 0;
const e5 = list.filter(value => (count++, value > 0)).length !== 0;
const e6 = list.filter(function (value) { return value > 1; }).length > 0;
const e7 = list.findIndex(predicate, receiver) !== -1;

// The `!` of the fix needs parentheses or a semicolon.
const p1 = (list.findIndex(x => x > 1) === -1).toString();
const p2 = (list.findIndex(x => x > 1) === -1 as boolean).valueOf();
const p3 = (list.findIndex(x => x > 1) < 0) ** 2;
let p4 = 1
;(list.findIndex(x => x > 1) == -1) && p4++
const p5 = `${list.findIndex(x => x > 1) === -1}`;
declare function setup(): void;
setup()
list.findIndex(x => x > 1) < 0 as any ** 2;
(list.findIndex(x => x > 1) < 0 as any) ** 2;
list.findLastIndex(x => x === /* keep */ 1) < 0 satisfies boolean as any ** 2;
