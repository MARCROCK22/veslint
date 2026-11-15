enum Fruit {
  Apple,
  Banana,
}
enum Vegetable {
  Carrot = 'carrot',
  Leek = 'leek',
}
enum Flags {
  Read = 1,
  Write = 2,
}
enum Ünï {
  A,
}
declare function dec(...args: unknown[]): any;
declare const n: number;
declare const str: string;
declare function takesFruit(f: Fruit): void;
declare function takesFruits(...f: Fruit[]): void;
declare function takesTuple(...f: [Fruit, Vegetable]): void;
declare function tag(strings: TemplateStringsArray, f: Fruit, v: Vegetable): string;
declare function generic<T extends Fruit>(t: T): T;

// Reported.
const a: Fruit = 1;
const b: Vegetable = 'carrot';
let c: Fruit = Fruit.Apple;
c = n;
c += 1;
c++;
--c;
const d: Fruit | Vegetable = str;
const e: Fruit[] = [1, Fruit.Apple, n];
const f: { fruit: Fruit; veg: Vegetable } = { fruit: 1, veg: 'leek' };
const g: Set<Fruit> = new Set<number>([1]);
const h: Map<Fruit, Vegetable[]> = new Map<number, string[]>();
takesFruit(1);
takesFruits(Fruit.Apple, 2, n);
takesFruits(...[Fruit.Apple, 1]);
takesTuple(1, 'leek');
takesTuple(...[Fruit.Apple, 'x'] as const);
tag`${1}${'x'}`;
generic(1);
const i = 1 as Fruit;
const j = <Vegetable>'x';
const k = (n satisfies number) as Fruit;
function l(): Fruit {
  return 1;
}
const m = (): Vegetable => 'x';
async function o(): Promise<Fruit> {
  return Promise.resolve(1);
}
function p(fruit: Fruit = 1, ü: Ünï = 0): void {}
const { q = 1 }: { q?: Fruit } = {};
class Klass {
  fruit: Fruit = 1;
  @dec decorated: Fruit = 2;
  accessor acc: Vegetable = 'x';
  get getter(): Fruit {
    return 0;
  }
  @dec
  method(): Fruit {
    return n;
  }
  static s: Fruit = n;
}
interface HasFruit {
  fruit: Fruit;
}
class Impl implements HasFruit {
  fruit = 1;
}
class Base {
  veg: Vegetable = Vegetable.Leek;
}
class Derived extends Base {
  veg = 'x';
}
declare const byFruit: { [key in Fruit]: string };
byFruit[2];
byFruit[n];
declare const byMember: { [Fruit.Apple]: string; [Vegetable.Leek]: string };
byMember[0];
const flagsBad: Flags = Flags.Read | 4;
const mixed: Fruit = n ? Fruit.Apple : 1;
const ü: Ünï = 1;
const nested: { a: { b: Fruit[] } } = { a: { b: [1] } };

// Not reported.
const ok1: Fruit = Fruit.Banana;
const ok2: Fruit | number = 1;
const ok3: Vegetable = Vegetable.Carrot;
const ok4: Flags = Flags.Read | Flags.Write;
let ok5: Flags = Flags.Read;
ok5 &= ~Flags.Write;
ok5 |= Flags.Write;
const ok6 = Fruit.Apple as Fruit;
takesFruit(Fruit.Apple);
takesFruits(...([] as Fruit[]));
function ok7(): Fruit {
  return Fruit.Apple;
}
async function ok8(): Promise<Fruit> {
  return Fruit.Apple;
}
const ok9: number = Fruit.Apple;
const ok10: string = Vegetable.Leek;
byFruit[Fruit.Apple];
const ok11: unknown = 1;
let ok12 = 1;
ok12 += 1;
const ok13: Fruit = generic(Fruit.Apple);
