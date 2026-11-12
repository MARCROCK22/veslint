// Aliases that only name a conditional type. A type asked through an alias imported from
// another file takes that alias, and its declaration is the one at the end of the chain.
export interface Changeable {
  a: number;
}
export type Keyed<P, V> = unknown extends P
  ? string | ((obj: P) => V)
  : string extends keyof P
    ? string | number
    : keyof P;
export type KeyedAlias<P, V = any> = Keyed<P, V>;
export type KeyedTwice<P, V> = KeyedAlias<P, V>;
export type KeyedParen<P, V> = (Keyed<P, V>);
export type Listed<T, V> = T extends string ? V[] : never;
export type ListedAlias<T, V> = Listed<T, V>;
export type Chosen<T, V> = T extends string ? V : never;
export type ChosenAlias<T, V> = Chosen<T, V>;
export type ChosenTwice<T, V> = ChosenAlias<T, V>;
export type ChosenOrNothing<T, V> = Chosen<T, V> | undefined;
export type NotConditional<V> = V[];
export type NotConditionalAlias<V> = NotConditional<V>;
