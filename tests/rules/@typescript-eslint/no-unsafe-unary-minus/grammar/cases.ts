// Type arguments without a call after `-`: `-f<T>` negates the instantiation expression `f<T>`,
// whose type has the type arguments applied.
declare function make<T>(): T;
declare const holder: { get<T>(): T; n: number };
const negatedFunction = -make<number>;
const negatedMethod = -holder.get<bigint>;
const negatedCall = -make<number>();
const negatedString = -make<string>();
const compared = holder.n < holder.n > -1;
export { negatedFunction, negatedMethod, negatedCall, negatedString, compared };
