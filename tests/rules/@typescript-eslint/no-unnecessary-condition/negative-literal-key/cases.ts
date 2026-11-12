// A number literal type names a property like Number::toString (`-1` → "-1", `-2.5` → "-2.5"):
// isNullablePropertyType finds the declared property, whose type may be nullish.
declare const u: { '-1': string | undefined } | null;
declare const k: -1;
export const n1 = u?.[k]?.length;

declare const v: { '-2.5': number | undefined } | null;
declare const j: -2.5;
export const n2 = v?.[j]?.toFixed();

// The property is not nullish: the second `?.` is unnecessary.
declare const w: { '-1': string } | null;
export const n3 = w?.[k]?.length;
