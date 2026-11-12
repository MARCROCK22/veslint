// no-unnecessary-type-constraint in a .tsx file: an arrow function with a lone type parameter keeps
// a comma (`<T,>`) so that it is not read as JSX, but when a comma or a default follows.
const a = <T extends unknown>(t: T): T => t;
const b = <T extends any,>(t: T): T => t;
const c = <T extends unknown = string>(t: T): T => t;
const d = <T extends unknown, U extends any>(t: T, u: U): [T, U] => [t, u];
function e<T extends unknown>(t: T): T {
  return t;
}
export { a, b, c, d, e };
