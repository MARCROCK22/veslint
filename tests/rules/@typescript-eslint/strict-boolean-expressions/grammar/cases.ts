// Type arguments without a call after `!`: the operand is the instantiation expression, and the
// suggestions wrap it whole.
declare function make<T>(): T;
declare const anyValue: any;
declare const maybe: (<T>() => T) | undefined;
const negatedAny = !anyValue<string>;
const negatedFunction = !make<number>;
const negatedNullable = !maybe<string>;
if (make<number>) {
}
const chosen = anyValue<number> ? 1 : 2;
export { negatedAny, negatedFunction, negatedNullable, chosen };
