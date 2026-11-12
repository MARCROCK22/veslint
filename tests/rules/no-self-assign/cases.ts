// no-self-assign with its default options (props: true).
let a = 1, b = 2, c = 3;
declare let o: { x: number; y: { z: number }; [key: string]: unknown };
declare let list: number[];

a = a;
(a) = a;
a = (a);
a &&= a;
a ||= a;
a ??= a;
a += a;
[a, b] = [a, b];
[a, , b] = [a, , b];
[a, ...list] = [a, ...list];
[...list] = [...list, 1];
({ a, b } = { a, b });
({ a: b } = { a: b });
({ a } = { ...o, a });
({ a } = { a, ...o });
o.x = o.x;
o['x'] = o.x;
o.y.z = o.y['z'];
o[a] = o[a];
o[0] = o['0'];
o.x = o.y;
o.x = o?.x;

class Counter {
  #count = 0;
  value = 0;
  reset() {
    this.#count = this.#count;
    this.value = this.value;
  }
}

// TypeScript's wrappers make another expression.
a = a as number;
a = a!;
(a as number) = a;
