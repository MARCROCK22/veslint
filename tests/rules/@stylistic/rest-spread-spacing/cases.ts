declare function fn(...args: unknown[]): void;
declare const args: number[];
declare const obj: { a: number; b: number };
let rest: unknown;

// Reported: spread in calls, new, arrays and objects.
fn(... args);
fn(...  args, ...	args);
new Array(... args);
const spreadArray = [... args, 1];
const spreadObject = { ... obj };
fn(... (args));
fn(...
	args);
fn(... /* comment */ args);
fn(.../* comment */args);
fn(.../* comment */ args);
const typed = [... /** @type {string} */ (args)];
const typedFine = [.../* a */ /* b */ (args)];

// Reported: rest elements in parameters, patterns and assignments.
function restParameter(... values: number[]): number[] {
	return values;
}
const restArrow = (first: number, ... others: number[]) => others;
const [firstItem, ... restItems] = args;
const { a, ... restProperties } = obj;
[rest, ... rest as unknown[]] = args;
({ ... rest } = obj);
for (const [... inner] of [args]) {
	fn(inner);
}
class WithRest {
	constructor(... parts: string[]) {
		fn(parts);
	}
	method(this: WithRest, ... parts: string[]): void {
		fn(parts);
	}
}

// Not reported.
fn(...args);
fn(...(args));
const fine = [...args, { ...obj }];
function fineRest(...values: number[]): number[] {
	return values;
}
type Tuple = [... number[]];
type Spread<T extends unknown[]> = [...T, string];
const { b, ...others } = obj;

export { typed, typedFine, spreadArray, spreadObject, restParameter, restArrow, firstItem, restItems, a, restProperties, WithRest, fine, fineRest, b, others };
export type { Tuple, Spread };
