// Aliases whose first condition is decided where they are declared: the type they give has the
// declaration of the conditional type in the branch taken.
export type Chosen<T, V> = T extends string ? V : never;
export type DecidedTrue<T, V> = string extends string ? Chosen<T, V> : V[];
export type DecidedFalse<T, V> = string extends number ? V[] : Chosen<T, V>;
export type DecidedNested<T, V> = string extends number ? V[] : T extends string ? V : never;
export type DecidedTrueAgain<T, V> = DecidedTrue<T, V>;
export type ChainTwoImported<T, W, V> = T extends string ? V[] : W extends number ? V : never;
export type ChainSameCheck<T, V> = T extends string ? V[] : T extends number ? V : never;
