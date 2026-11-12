// prefer-readonly-parameter-types: a conditional type is as readonly as its branches are where it
// is declared, whatever the type arguments of the use.
import type {
  Changeable,
  ChosenAlias,
  ChosenOrNothing,
  ChosenTwice,
  Keyed,
  KeyedAlias,
  KeyedParen,
  KeyedTwice,
  ListedAlias,
  NotConditionalAlias,
} from './imported';
interface Mutable {
  a: number;
}
interface Frozen {
  readonly a: number;
}
type Pick1<T, V> = T extends string ? V : never;
type PickParen<T, V> = (T extends string ? V : never);
type PickArray<T, V> = T extends string ? V[] : never;
type PickReadonlyArray<T, V> = T extends string ? readonly V[] : never;
type Chain<T, V> = T extends string ? V : T extends number ? readonly V[] : never;
type ChainMutable<T, V> = T extends string ? V : T extends number ? V[] : never;
type ChainMixed<T, V> = T extends string ? V[] : T extends number ? readonly V[] : never;
type ChainThree<T, V> = T extends string ? V : T extends number ? V[] : T extends boolean ? Frozen : never;
type ChainTwoParameters<T, W, V> = T extends string ? V[] : W extends number ? V : never;
type ChainGenericExtends<T, W, V> = T extends W ? V[] : W extends number ? V : never;
type ChainSameExtends<T, W, V> = T extends string ? V[] : W extends string ? V : never;
type ChainExtendsParameter<T, W, V> = T extends string ? V[] : T extends W ? V : never;
type ChainExtendsParameterMutable<T, W, V> = T extends string ? V : T extends W ? V[] : never;
type NestedTrue<T, V> = T extends string ? (T extends 'a' ? V : readonly V[]) : never;
type NestedTrueMutable<T, V> = T extends string ? (T extends 'a' ? V : V[]) : never;
type NestedFalseParen<T, V> = T extends string ? V[] : (T extends number ? V : never);
type Indirect<T, V> = Pick1<T, V>;
type ViaAlias<T, V> = T extends string ? Pick1<T, V> : never;
type ViaAliasMutable<T, V> = T extends string ? PickArray<T, V> : never;
type WithInfer<T, V> = T extends (infer E)[] ? V : never;
type Recursive<T> = T extends [infer Head, ...infer Rest] ? [Head, ...Recursive<Rest>] : [];
type RecursiveReadonly<T> = T extends readonly [infer Head, ...infer Rest] ? readonly [Head, ...RecursiveReadonly<Rest>] : readonly [];
type ToMutable<T> = T extends string ? Mutable : Frozen;
type ToFrozen<T> = T extends string ? Frozen : Readonly<Mutable>;

function aliases<U>(
  a: Pick1<U, Mutable>,
  b: PickParen<U, Mutable>,
  c: PickArray<U, Mutable>,
  d: PickReadonlyArray<U, Mutable>,
  e: Pick1<U, Mutable[]>,
  f: Pick1<U, readonly Frozen[]>,
  g: ToMutable<U>,
  h: ToFrozen<U>,
) {}
function chains<U>(
  a: Chain<U, Mutable>,
  b: ChainMutable<U, Mutable>,
  c: ChainMixed<U, Mutable>,
  d: ChainThree<U, Mutable>,
  e: ChainMixed<U, Frozen>,
) {}
// The first condition is decided, and the type is the conditional type in the false branch.
function decided<U>(
  a: ChainExtendsParameter<number, U, Frozen>,
  b: ChainTwoParameters<string, U, Mutable>,
  c: ChainTwoParameters<U, number, Mutable>,
  d: ChainMixed<boolean | U, Mutable>,
  e: Chain<number, Mutable>,
  f: Chain<string, Mutable>,
  g: ChainSameExtends<symbol, U, Frozen>,
  h: ChainTwoParameters<bigint, U, Frozen>,
  i: ChainGenericExtends<symbol, U, Frozen>,
  j: ChainExtendsParameterMutable<number, U, Mutable>,
  k: ChainExtendsParameter<string, U, Mutable>,
  l: ChainExtendsParameter<U, number, Mutable>,
) {}
function nested<U extends string>(
  a: NestedTrue<U, Mutable>,
  b: NestedTrueMutable<U, Mutable>,
  c: NestedFalseParen<U, Mutable>,
  d: NestedTrue<'b', Mutable>,
) {}
function indirect<U>(
  a: Indirect<U, Mutable>,
  b: ViaAlias<U, Mutable>,
  c: ViaAliasMutable<U, Mutable>,
  d: WithInfer<U, Mutable>,
  e: Recursive<U>,
  f: RecursiveReadonly<U>,
  g: U extends string ? Mutable : never,
  h: U extends string ? Frozen : readonly Frozen[],
) {}
function unions<U>(a: Pick1<U, Mutable> | undefined, b: PickArray<U, Mutable> | Frozen, c: { readonly inner: Pick1<U, Mutable> }) {}
function imported<P, V, U>(
  a: KeyedAlias<P, V>,
  b: KeyedAlias<P, V> | undefined,
  c: KeyedTwice<P, V>,
  d: KeyedParen<P, V>,
  e: ListedAlias<U, Changeable>,
  f: ChosenAlias<U, Changeable>,
  g: ChosenTwice<U, Changeable>,
  h: ChosenOrNothing<U, Changeable>,
  i: NotConditionalAlias<U>,
  j: Keyed<P, V>,
) {}
export { aliases, chains, decided, nested, indirect, unions, imported };
