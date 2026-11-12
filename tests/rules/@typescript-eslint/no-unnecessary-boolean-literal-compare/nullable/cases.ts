declare const flag: boolean;
declare const maybe: boolean | undefined;
declare const maybeNull: boolean | null;
declare const maybeTrue: true | undefined;
declare const mixed: boolean | string | undefined;
declare const nothing: null | undefined;

// Nullable booleans with both options turned off.
const a = maybe === true;
const b = maybe !== true;
const c = maybe == false;
const d = maybe != false;
const e = true === maybeNull;
const f = maybeTrue === true;
const g = flag === false;
// Not nullable booleans.
const h = mixed === true;
const i = nothing === false;

function nullableConstraint<T extends boolean | null>(value: T): boolean {
  return value !== true;
}

export { a, b, c, d, e, f, g, h, i, nullableConstraint };
