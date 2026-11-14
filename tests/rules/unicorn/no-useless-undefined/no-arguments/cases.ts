declare function fn(...values: unknown[]): unknown;

// `checkArguments` does nothing in a TypeScript file.
fn(undefined);
fn(1, undefined);

// The rest is still checked.
const arrowBody = () => undefined;
let value = undefined;
export {arrowBody, value};
