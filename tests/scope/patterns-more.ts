// More targets with assertions.
type T = number;
declare let x: any, y: any, o: any;
declare const a: any[], xs: any[];
class K {
  k = 1;
  m() {
    [(x as typeof this.k)] = a;
    [(x as this)] = a;
    [this.k, (this as K).k] = a;
  }
}
[(x as typeof o.p.q<T>)] = a;
[(x as typeof import('m'))] = a;
[(x as typeof import('m').z)] = a;
[(x as import('m').a.b.C)] = a;
[(x as { [y]: T; ['lit']: T; [o.p]: T; 0: T; 'q': T })] = a;
[(x as <G extends T = T>(p: G, { q }: G, [r]: G[], ...s: G[]) => G)] = a;
[(x as { m<G>(p: G): G; get g(): T; set g(v: T) })] = a;
[(x as (T | T)[][])] = a;
[(x as [T?, ...T[]])] = a;
[(x as -1 | 'a' | true | null | undefined | void | 1n | never)] = a;
[(x as T extends [infer H extends T, ...infer R] ? [H, R] : never)] = a;
[(x as Array<Map<T, Set<T>>>)] = a;
[<const>x] = a;
[<T>(<T>x)] = a;
({ a: x as T, b: [y as T], ...(o as T) } = a as any);
({ x = y as T, [x as T]: y } = o);
[x as T, y satisfies T, o!] = a;
[[x as T]] = a;
for ([x as T, { y }] of xs) {}
for ({ y = x as T } of xs) {}
for ([(x as T)] of xs) {}
for ([...(x as T)] of xs) {}
for ({ k: x as T } of xs) {}
for ((<T>x) in o) {}
for ((x!) of xs) {}
for ((x satisfies T) of xs) {}
[(x as T as T)] = a;
[((x as T)!) as T] = a;
(x as const) = 1;
(<const>x) = 1;
export {};
