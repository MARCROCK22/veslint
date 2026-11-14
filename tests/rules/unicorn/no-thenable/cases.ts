declare let foo: Record<string, unknown>;
const key = 'then';

// Reported.
const a1 = { then() {} };
const a2 = { get then() { return 1; } };
const a3 = { [key]: 1 };
const a4 = { 'then': 1 };
class A5 { then() {} }
class A6 { static then = 1; }
class A7 { get [key]() { return 1; } }
foo.then = 1;
foo[key] = 1;
Object.defineProperty(foo, 'then', { value: 1 });
Reflect.defineProperty(foo, key, { value: 1 });
const a8 = Object.fromEntries([['then', 1], ['other', 2]]);
export function then() {}
export const [then2, then3] = [1, 2];

// Not reported.
const k1 = { thenable: 1 };
const k2 = foo.then;
class K3 { #then = 1; }
const k4 = { [`th${'en'}x`]: 1 };
let mutable = 'then';
const k5 = { [mutable]: 1 };
mutable = 'other';
export { a1, a2, a3, a4, A5, A6, A7, a8, k1, k2, K3, k4, k5 };
