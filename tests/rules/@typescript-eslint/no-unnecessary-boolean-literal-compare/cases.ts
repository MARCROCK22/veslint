declare const flag: boolean;
declare const yes: true;
declare const no: false;
declare const maybe: boolean | undefined;
declare const maybeNull: boolean | null;
declare const num: number;
declare const anyValue: any;
declare const text: string | boolean;
declare const nothing: null | undefined;

// Plain booleans: direct and negated comparisons.
if (flag === true) {
}
if (flag !== true) {
}
if (flag == false) {
}
if (flag != false) {
}
// The literal on the left.
if (true === flag) {
}
if (false !== flag) {
}
// Parentheses are not ESTree nodes.
if ((flag) === (true)) {
}
const wrapped = !(flag == true);
// Boolean literal types.
const a = yes === true;
const b = no !== false;
// Both sides are literals: the right one is the literal compared against.
const c = true === false;
// Nullable booleans are allowed by default.
const d = maybe === true;
const e = maybe !== true;
const f = maybe === false;
const g = maybeNull == false;
// Not booleans.
const h = num === 1;
const i = anyValue === true;
const j = text === true;
const k = nothing === true;
const l = (flag as boolean) === (true as boolean);
const m = flag < true;
const n = flag === !0;

// Type parameters: their constraint decides.
function constrained<T extends boolean>(value: T): boolean {
  return value === true;
}
function nullableConstraint<T extends boolean | undefined>(value: T): boolean {
  return value === false;
}
function unconstrained<T>(value: T): boolean {
  return value === true;
}
function literalConstraint<T extends true>(value: T): boolean {
  return value != true;
}

export { wrapped, a, b, c, d, e, f, g, h, i, j, k, l, m, n, constrained, nullableConstraint, unconstrained, literalConstraint };
