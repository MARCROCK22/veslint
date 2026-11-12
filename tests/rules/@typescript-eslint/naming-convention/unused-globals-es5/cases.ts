// The same with the lib of ES5: `Map`, `Promise` and `Symbol` are ESLint's globals for the
// ecmaVersion, and of them only `Symbol` is an implicit variable of the lib (a type).
/* exported Set */
Promise;
export const a = class Map {};
export const b = class Set {};
export const c = class Promise {};
export const d = class Symbol {};
export const e = class Object {};
export const f = class WeakMap {};
