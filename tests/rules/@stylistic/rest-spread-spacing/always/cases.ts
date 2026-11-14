declare function fn(...args: unknown[]): void;
declare const args: number[];
declare const obj: { a: number; b: number };

// Reported.
fn(...args);
new Array(...args);
const spreadArray = [...args, 1];
const spreadObject = { ...obj };
fn(...(args));
fn(.../* comment */args);
function restParameter(...values: number[]): number[] {
	return values;
}
const [firstItem, ...restItems] = args;
const { a, ...restProperties } = obj;

// Not reported.
fn(... args);
fn(...	args);
fn(...
	args);
fn(... /* comment */ args);
fn(.../* comment */ args);
const fine = [... args, { ... obj }];
function fineRest(... values: number[]): number[] {
	return values;
}
const { b, ... others } = obj;
type Tuple = [...number[]];

export { spreadArray, spreadObject, restParameter, firstItem, restItems, a, restProperties, fine, fineRest, b, others };
export type { Tuple };
