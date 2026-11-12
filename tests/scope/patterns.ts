// Assignment targets: what PatternVisitor reaches through `as`, `<T>`, `!` and `satisfies`.
type T = number;
type U = T;
namespace A {
  export type B = number;
}
interface P {
  k: T;
}
let x: any, y: any, z: any, k: any;
declare const a: any[], o: any, xs: any[];
[(x as T)] = a;
[<T>x] = a;
[x!] = a;
[x satisfies T] = a;
({ a: (x as T), b: y = z } = o);
[(x as typeof y)] = a;
[(x as A.B)] = a;
[(x as { k: T; m(p: T): U; [i: string]: U; new (q: T): U; (r: T): U })] = a;
[(x as (p: T) => U)] = a;
[(x as new (p: T) => U)] = a;
[(x as T[])] = a;
[(x as [T, U])] = a;
[(x as [first: T, second?: U, ...rest: T[]])] = a;
[(x as T | U)] = a;
[(x as T & U)] = a;
[(x as T extends U ? P : A.B)] = a;
[(x as T extends Array<infer I> ? I : never)] = a;
[(x as { [K in keyof P]: P[K] })] = a;
[(x as { [K in keyof P as `${K}x`]?: P[K] })] = a;
[(x as keyof P)] = a;
[(x as P['k'])] = a;
[(x as `a${T}b`)] = a;
[(x as import('m').Q<T>)] = a;
[(x as 'lit')] = a;
[(x as const)] = a;
[(x as Array<T>)] = a;
[(x as typeof A)] = a;
[(x as readonly T[])] = a;
[(x as unique symbol)] = a;
[(x as (this: T, ...rest: U[]) => asserts rest is T[])] = a;
[...(x as T)] = a;
[(x as T) = y] = a;
[[(x as T)], { k: [(y as U)] }] = a;
[x.y, x[z], (x as T).y, (y as U)[z as T]] = a;
({ [k]: x, y = k, ...z } = o);
for ((x as T) of xs) {}
for ([(x as T)] of xs) {}
for ((x as T) in o) {}
for (x.y of xs) {}
(x as T) = 1;
(<T>x) = 1;
x! = 1;
(x satisfies T) = 1;
(x as T) += 1;
(x as T)++;
--(<T>x);
x!++;
((x as T) as U) = 1;
(x!)! = 1;
[(x as T)!] = a;
[(x! as T)] = a;
[x = y, [z = x]] = a;
[x, , y] = a;
export { x, y, z, k };
