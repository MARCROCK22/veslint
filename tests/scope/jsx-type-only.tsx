/* global React */
// A variable that is only a type takes the reference of the pragma, which then resolves upwards.
type React = { createElement: unknown };
export const a: React | null = null;
export const b = <div />;
