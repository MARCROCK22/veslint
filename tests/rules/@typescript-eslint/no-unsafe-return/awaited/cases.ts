// Cases of no-unsafe-return in async functions, where the rule asks the checker for awaited types
// (getAwaitedType): thenables whose `then` has overloads, type parameters, a `this` parameter or a
// rest parameter, unions, type parameters (`Awaited<T>`) and promises of themselves.
declare const anyValue: any;
declare const anyArray: any[];
declare const promiseAny: Promise<any>;
declare const promiseLikeAny: PromiseLike<any>;
declare const promiseLikeString: PromiseLike<string>;
declare const nestedAny: Promise<Promise<any>>;
declare const nestedLikeAny: PromiseLike<Promise<PromiseLike<any>>>;

// A `then` with overloads: the callbacks of all of them count together.
declare const overloadedAny: { then(cb: (v: any) => void): void; then(cb: (v: string) => void, x: number): void };
declare const overloadedLast: { then(cb: (v: string) => void): void; then(cb: (v: any) => void, x: number): void };
declare const overloadedSafe: { then(cb: (v: string) => void): void; then(cb: (v: number) => void, x: number): void };
declare const overloadedSame: { then(cb: (v: any) => void): void; then(cb: (v: any) => void, x: number): void };
declare const noParameters: { then(): void; then(cb: (v: any) => void): void };
// With an overload whose first parameter is not a callback there is no promised type.
declare const mixedOverloads: { then(x: number): void; then(cb: (v: any) => void): void };
declare const mixedOptional: { then(x?: number): void; then(cb: (v: any) => void): void };
async function overloads1() { return overloadedAny; }
async function overloads2() { return overloadedLast; }
async function overloads3() { return overloadedSafe; }
async function overloads4() { return overloadedSame; }
async function overloads5() { return noParameters; }
async function overloads6() { return mixedOverloads; }
async function overloads7() { return mixedOptional; }

// A callback with overloads, or several callbacks.
declare const overloadedCallback: { then(cb: { (v: string): void; (v: any, w: number): void }): void };
declare const unionCallback: { then(cb: ((v: string) => void) | ((v: any) => void)): void };
declare const nullableCallback: { then(cb?: ((v: any) => void) | null): void };
declare const notCallable: { then(cb: number): void };
declare const anyCallback: { then(cb: any): void };
declare const anyThen: { then: any };
declare const optionalThen: { then?: (cb: (v: any) => void) => void };
async function callbacks1() { return overloadedCallback; }
async function callbacks2() { return unionCallback; }
async function callbacks3() { return nullableCallback; }
async function callbacks4() { return notCallable; }
async function callbacks5() { return anyCallback; }
async function callbacks6() { return anyThen; }
async function callbacks7() { return optionalThen; }

// A generic `then`.
declare const genericThen: { then<T>(cb: (v: T) => void): void };
declare const genericAnyThen: { then<T>(cb: (v: T | any) => void): void };
class Thenable<T> {
  constructor(readonly value: T) {}
  then<R1 = T, R2 = never>(
    ok?: ((value: T) => R1 | PromiseLike<R1>) | null,
    fail?: ((reason: unknown) => R2 | PromiseLike<R2>) | null,
  ): Thenable<R1 | R2> {
    void [ok, fail];
    return this as never;
  }
}
declare const thenableAny: Thenable<any>;
declare const thenableString: Thenable<string>;
declare const thenableNested: Thenable<Thenable<Promise<any>>>;
async function generics1() { return genericThen; }
async function generics2() { return genericAnyThen; }
async function generics3() { return thenableAny; }
async function generics4() { return thenableString; }
async function generics5() { return thenableNested; }
async function generics6(): Promise<string> { return thenableAny; }
async function generics7(): Promise<unknown> { return thenableAny; }
async function generics8(): Promise<any> { return thenableAny; }

// A `then` with a `this` parameter is a candidate only for a type that fits it.
declare const wrongThis: { then(this: { other: number }, cb: (v: any) => void): void };
declare const voidThis: { then(this: void, cb: (v: any) => void): void };
declare const anyThis: { then(this: any, cb: (v: any) => void): void };
class OwnThis {
  then(this: OwnThis, cb: (v: any) => void): void { void cb; }
}
declare const ownThis: OwnThis;
declare const oneWrongThis: { then(this: { other: number }, cb: (v: any) => void): void; then(cb: (v: string) => void, x: number): void };
async function thisParameter1() { return wrongThis; }
async function thisParameter2() { return voidThis; }
async function thisParameter3() { return anyThis; }
async function thisParameter4() { return ownThis; }
async function thisParameter5() { return oneWrongThis; }

// A rest parameter: the callback is its first element.
declare const restTuple: { then(...args: [cb: (v: any) => void]): void };
declare const restArray: { then(...cbs: Array<(v: any) => void>): void };
declare const restSafe: { then(...args: [cb: (v: string) => void, x?: any]): void };
async function rest1() { return restTuple; }
async function rest2() { return restArray; }
async function rest3() { return restSafe; }

// A promise of itself has no awaited type, and two missing awaited types are the same.
interface Self<X> { then(cb: (v: Self<X>) => void): void; value: X }
interface Ping<X> { then(cb: (v: Pong<X>) => void): void; value: X }
interface Pong<X> { then(cb: (v: Ping<X>) => void): void; value: X }
interface Settles<X> { then(cb: (v: X[]) => void): void; value: X }
declare const selfAny: Self<any>;
declare const pingAny: Ping<any>;
declare const settlesAny: Settles<any>;
async function recursive1(): Self<string> { return selfAny; }
async function recursive2(): Ping<string> { return pingAny; }
async function recursive3(): Settles<string> { return settlesAny; }
async function recursive4(): Self<string> { return settlesAny; }
async function recursive5() { return selfAny; }

// Unions: the awaited types of the members.
declare const unionAny: Promise<any> | string;
declare const unionSafe: Promise<string> | number;
declare const unionArrays: Promise<any[]> | any[];
declare const unionSets: Promise<Set<any>> | undefined;
declare const unionWrong: typeof wrongThis | Promise<any>;
type Aliased = Set<any> | undefined;
async function unions1() { return unionAny; }
async function unions2() { return unionSafe; }
async function unions3(): Promise<string | number> { return unionSafe; }
async function unions4() { return unionArrays; }
async function unions5(): Promise<any[]> { return unionArrays; }
async function unions6(): Promise<Set<any> | undefined> { return unionSets; }
async function unions7(): Promise<Aliased> { return unionSets; }
async function unions8() { return unionWrong; }
async function unions9(): Promise<string> { return unionAny; }

// The awaited types are compared.
async function same1(): Promise<any[]> { return anyArray; }
async function same2(): Promise<string[]> { return anyArray; }
async function same3(): Promise<Promise<any[]>> { return anyArray; }
async function same4(): Promise<Set<any>> { return new Set<any>(); }
async function same5(): Promise<Set<string>> { return new Set<any>(); }
async function same6(): Promise<Set<string>> { return Promise.resolve(new Set<any>()); }
async function same7(): Promise<Set<any>> { return Promise.resolve(new Set<any>()); }
async function same8(): Promise<unknown> { return promiseAny; }
async function same9(): Promise<PromiseLike<unknown>> { return nestedAny; }
async function same10(): Promise<string> { return nestedLikeAny; }
async function same11(): Promise<string> { return promiseLikeString; }
function notAsync1() { return promiseLikeAny; }
function notAsync2(): Promise<string> { return promiseAny; }

// Type parameters: `Awaited<T>`.
async function parameters1<T>(x: T): Promise<T> { return x; }
async function parameters2<T>(x: T): Promise<Awaited<T>> { return x; }
async function parameters3<T>(x: T): Promise<Awaited<T>> { void x; return anyValue; }
async function parameters4<T extends Promise<any>>(x: T) { return x; }
async function parameters5<T extends PromiseLike<any>>(x: T): Promise<Awaited<T>> { return x; }
async function parameters6<T extends string>(x: T): Promise<T> { return x; }
async function parameters7<T extends string>(x: T): Promise<T> { void x; return anyValue; }
async function parameters8<T>(x: T | Promise<any>) { return x; }
async function parameters9<T>(x: T[]): Promise<T[]> { void x; return anyArray; }
async function parameters10<T>(x: Promise<T>): Promise<Set<T>> { void x; return new Set<any>(); }
async function parameters11<T extends object>(x: T & { then(cb: (v: any) => void): void }) { return x; }

// A primitive with a `then` is not unwrapped.
declare const branded: string & { then(cb: (v: any) => void): void };
async function primitives1() { return branded; }
async function primitives2<T extends string & { then(cb: (v: any) => void): void }>(x: T) { return x; }

// The callbacks of several `then` signatures are resolved together: the one whose parameters are
// subtypes of those of the others stays, and unrelated ones are combined.
declare const unrelated: { then(cb: (v: string) => void): void; then(cb: (v: number) => void, x: number): void };
declare const unrelatedAny: { then(cb: (v: { a: any }) => void): void; then(cb: (v: { b: any }) => void, x: number): void };
declare const unrelatedPromise: { then(cb: (v: Promise<any>) => void): void; then(cb: (v: { b: 1 }) => void, x: number): void };
declare const twice: { then(cb: (v: { a: any }) => void): void; then(cb: (v: { a: any }) => void, x: number): void };
declare const longerAny: { then(cb: (v: any, w: string) => void): void; then(cb: (v: string) => void, x: number): void };
declare const optionalAny: { then(cb: (v?: any) => void): void; then(cb: (v: string) => void, x: number): void };
declare const optionalString: { then(cb: (v: any) => void): void; then(cb: (v?: string) => void, x: number): void };
declare const genericCallbacks: { then(cb: <U>(v: U) => void): void; then(cb: (v: any) => void, x: number): void };
declare const restCallbacks: { then(cb: (...v: any[]) => void): void; then(cb: (v: string) => void, x: number): void };
declare const thisCallbacks: { then(cb: (this: void, v: any) => void): void; then(cb: (v: string) => void, x: number): void };
declare const overloadedCallbacks: { then(cb: { (v: any): void; (v: string, w: number): void }): void; then(cb: (v: string) => void, x: number): void };
declare const threeOverloads: { then(cb: (v: any) => void): void; then(cb: (v: string) => void, x: number): void; then(cb: (v: 'a') => void, x: number, y: number): void };
declare const unknownAndAny: { then(cb: (v: unknown) => void): void; then(cb: (v: any) => void, x: number): void };
async function together1() { return unrelated; }
async function together2() { return unrelatedAny; }
async function together3() { return unrelatedPromise; }
async function together4() { return twice; }
async function together5() { return longerAny; }
async function together6() { return optionalAny; }
async function together7() { return optionalString; }
async function together8() { return genericCallbacks; }
async function together9() { return restCallbacks; }
async function together10() { return thisCallbacks; }
async function together11() { return overloadedCallbacks; }
async function together12() { return threeOverloads; }
async function together13() { return unknownAndAny; }
async function together14(): Promise<unknown> { return unknownAndAny; }

// A type parameter with a mapped or empty constraint, and a union with an alias.
async function constraints1<T extends { [K in never]: string }>(x: T, y: any): Promise<Awaited<T>> { void x; return y; }
async function constraints2<T extends { [K in never]: string }>(x: T): Promise<Awaited<T>> { return x; }
async function constraints3<T extends {}>(x: T): Promise<T> { return x; }
type Mixed = string | number;
declare const mixedPromise: Promise<any[]> | Mixed;
async function constraints4(): Promise<Mixed | any[]> { return mixedPromise; }

void [together1, together2, together3, together4, together5, together6, together7, together8];
void [together9, together10, together11, together12, together13, together14];
void [constraints1, constraints2, constraints3, constraints4];
void [overloads1, overloads2, overloads3, overloads4, overloads5, overloads6, overloads7];
void [callbacks1, callbacks2, callbacks3, callbacks4, callbacks5, callbacks6, callbacks7];
void [generics1, generics2, generics3, generics4, generics5, generics6, generics7, generics8];
void [thisParameter1, thisParameter2, thisParameter3, thisParameter4, thisParameter5];
void [rest1, rest2, rest3, recursive1, recursive2, recursive3, recursive4, recursive5];
void [unions1, unions2, unions3, unions4, unions5, unions6, unions7, unions8, unions9];
void [same1, same2, same3, same4, same5, same6, same7, same8, same9, same10, same11];
void [notAsync1, notAsync2, parameters1, parameters2, parameters3, parameters4, parameters5];
void [parameters6, parameters7, parameters8, parameters9, parameters10, parameters11];
void [primitives1, primitives2];

// The cases the port of getAwaitedType could not decide before TypeScript 7.1 put it in the API.
// A `this` the type is assignable to but not a subtype of: it lacks an optional property.
declare const thisOptional: { x: number; then(this: { x: number; y?: string }, cb: (v: any) => void): void };
declare const thisSame: { x: number; then(this: { x: number }, cb: (v: any) => void): void };
async function thisOptional1() { return thisOptional; }
async function thisSame1() { return thisSame; }
// The callbacks of several `then` signatures: with type parameters, a tuple rest or unrelated
// parameters.
declare const genericCallbacks: { then(cb: <T>(v: T) => void): void; then(cb: (v: any) => void, x: number): void };
declare const tupleRest: { then(cb: (...args: [any]) => void): void; then(cb: (v: string) => void, x: number): void };
declare const unrelated: { then(cb: (v: { a: any }) => void): void; then(cb: (v: { b: string }) => void, x: number): void };
async function genericCallbacks1() { return genericCallbacks; }
async function tupleRest1() { return tupleRest; }
async function unrelated1() { return unrelated; }
// A mapped type without members.
type MappedOf<T> = { [K in keyof T]: T[K] };
declare const emptyMapped: MappedOf<{}>;
declare const promiseOfEmptyMapped: Promise<MappedOf<{}>>;
async function emptyMapped1() { return emptyMapped; }
async function emptyMapped2() { return promiseOfEmptyMapped; }
