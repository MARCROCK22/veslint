declare function fn(...values: unknown[]): unknown;

// Not reported: `checkArrowFunctionBody` is off.
const arrowBody = () => undefined;
fn(() => (undefined));

// Still reported.
const arrowReturn = () => {
	return undefined;
};
let value = undefined;
fn(undefined);
export {arrowBody, arrowReturn, value};
