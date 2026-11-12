// Type arguments without a call as the right operand of `+`: `a + f<T>` adds the instantiation
// expression `f<T>`, not `(a + f)<T>`.
declare function make<T>(): T;
declare const holder: { get<T>(): T };
const added = 'a' + make<string>;
const addedMethod = 1 + holder.get<number>;
const addedCall = 'a' + make<string>();
const addedLeft = make<number> + 1;
export { added, addedMethod, addedCall, addedLeft };
