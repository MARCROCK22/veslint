// The `!` that ends an optional chain is inside its ChainExpression: not the left side of the `=`.
declare const c: { d: number } | undefined;
declare const e: { f: number | undefined };
declare const b: number;
c?.d! = b;
e.f! = b;
(c?.d)! = b;
const g = c?.d!;
export { g };
