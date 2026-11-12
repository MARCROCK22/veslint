// no-unnecessary-type-parameters: instances of generic mapped types without an alias (what a
// call to a generic function returns), whose type parameter and template the tsgo API does not
// give.
declare function mapKeys<M>(value: M): { [K in keyof M]: string };
declare function mapValue<M, V>(value: M, other: V): { [K in keyof M]: V };
declare function mapBoth<M>(value: M): { [K in keyof M]: M[K] };
declare function mapNames<N extends string, V>(name: N, other: V): { [K in N]: V };
declare function mapRenamed<M, V>(value: M, other: V): { [K in keyof M as `get${K & string}`]: V };
declare function mapExcluded<M, X>(value: M, excluded: X): { [K in Exclude<keyof M, X>]: string };
declare function mapIndexed<M>(value: M): { [key: string]: M };
declare function mapNested<M, V>(value: M, other: V): { inner: { [K in keyof M]: V } };
declare function mapArray<M, V>(value: M, other: V): { [K in keyof M]: V }[];
declare function mapPartial<M>(value: M): Partial<M>;

// The keys use the type parameter: once in the parameter and once in the instance.
function keysOnly<T>(value: T) {
  return mapKeys(value);
}
// The template uses W, the keys do not.
function templateOnly<T, W>(value: T, other: W) {
  return mapValue(value, other);
}
function templateTwice<T>(value: T) {
  return mapBoth(value);
}
function namesOnly<T extends string, W>(name: T, other: W) {
  return mapNames(name, other);
}
function renamed<T, W>(value: T, other: W) {
  return mapRenamed(value, other);
}
function excluded<T, W>(value: T, other: W) {
  return mapExcluded(value, other);
}
function indexed<T>(value: T) {
  return mapIndexed(value);
}
function nested<T, W>(value: T, other: W) {
  return mapNested(value, other);
}
function inArray<T, W>(value: T, other: W) {
  return mapArray(value, other);
}
function partial<T>(value: T) {
  return mapPartial(value);
}
// Nothing but the instance uses the type parameter.
function instanceOnly<T>() {
  return mapKeys(null! as T);
}
function instanceTemplateOnly<T, W>(value: T) {
  return mapValue(value, null! as W);
}
// The type arguments of the call are not type parameters.
function concrete<T>(value: T) {
  return [value, mapKeys({ a: 1 }), mapValue({ a: 1 }, 2)];
}
const arrow = <T, W>(value: T, other: W) => mapValue(value, other);
class Methods {
  method<T, W>(value: T, other: W) {
    return mapValue(value, other);
  }
}
// A type parameter of an outer function with the same name is another one.
function shadowed<T>(value: T) {
  function inner<T>(other: T) {
    return [other, mapKeys(value)] as const;
  }
  function innerOwn<T>(other: T) {
    return mapKeys(other);
  }
  function innerBoth<T, W>(other: T, last: W) {
    return [mapValue(value, last), mapExcluded(value, other)] as const;
  }
  return [inner, innerOwn, innerBoth] as const;
}
// The type arguments of a generic alias count as used several times.
function aliasOnly<T, W>(value: T) {
  return mapExcluded(value, null! as W);
}
function aliasKeys<T, W>(other: W) {
  return mapExcluded(null! as T, other);
}
// Keys that are a type parameter with a constraint, a template literal, an intersection.
declare function mapUpper<N extends string>(name: N): { [K in Uppercase<N>]: number };
declare function mapPrefixed<N extends string>(name: N): { [K in `on${N}`]: number };
declare function mapBounded<M, N extends keyof M>(value: M, name: N): { [K in N]: M[K] };
declare function mapBoundedOther<N extends string>(name: N): { [K in N & `x${string}`]: number };
function upper<T extends string>() {
  return mapUpper(null! as T);
}
function prefixed<T extends string>() {
  return mapPrefixed(null! as T);
}
function bounded<T, N extends keyof T>(value: T) {
  return mapBounded(value, null! as N);
}
function boundedOther<T extends string>() {
  return mapBoundedOther(null! as T);
}
// An instance with properties: they are looked at, not the keys.
function withProperties<T, W>(other: W) {
  return [mapValue({ a: 1 }, other), mapKeys(null! as { a: T })] as const;
}
class Keeper<T> {
  keys!: { [K in keyof T]: string };
  method<W>(other: W) {
    return [mapValue(this.keys, other), new Keeper<T[]>().keys] as const;
  }
}
export { shadowed, aliasOnly, aliasKeys, upper, prefixed, bounded, boundedOther, withProperties, Keeper };
export { keysOnly, templateOnly, templateTwice, namesOnly, renamed, excluded, indexed, nested, inArray, partial, instanceOnly, instanceTemplateOnly, concrete, arrow, Methods };
