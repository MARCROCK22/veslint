import { Remote } from './other';

enum Fruit {
  Apple,
  Banana,
}
enum Vegetable {
  Lettuce,
  Carrot,
}
enum Color {
  Red = 'red',
  Blue = 'blue',
}
enum Single {
  Only,
}
enum Mixed {
  One = 1,
  Text = 'text',
}
const enum Constant {
  A = 1,
  B = 2,
}
declare const fruit: Fruit;
declare const apple: Fruit.Apple;
declare const vegetable: Vegetable;
declare const color: Color;
declare const single: Single;
declare const mixed: Mixed;
declare const constant: Constant;
declare const remote: Remote;
declare const num: number;
declare const text: string;
declare const anyValue: any;
declare const unknownValue: unknown;
declare const fruitOrNumber: Fruit | number;
declare const fruitOrVegetable: Fruit | Vegetable;
declare const appleOrZero: Fruit.Apple | 0;
declare const branded: number & { brand: true };
declare const textOrNumber: string | number;

// Comparisons that share an enum, or a type, are fine.
fruit === Fruit.Apple;
apple === Fruit.Banana;
fruit === fruit;
color !== Color.Blue;
appleOrZero === 0;
fruitOrVegetable === Vegetable.Carrot;
remote === Remote.Second;
num === 1;
fruit === anyValue;
fruit === unknownValue;
color === num;
fruit === text;

// Mismatched comparisons.
fruit === 0;
0 === fruit;
fruit == 1;
fruit != num;
fruit < 1;
fruit >= num;
fruit === vegetable;
fruitOrNumber === 1;
color === 'red';
color === text;
color < 'b';
single === 0;
mixed === 1;
mixed === 'text';
constant === 1;
remote === 2;
fruit === branded;
fruit === textOrNumber;
(fruit) === (0);

// Other operators are not checked.
fruit + 1;
fruit << 1;

// Switch cases.
switch (fruit) {
  case Fruit.Apple:
    break;
  case 1:
    break;
  case num:
    break;
  default:
    break;
}
switch (color) {
  case 'red':
    break;
  case Color.Blue:
    break;
  case (text):
    break;
}
switch ((remote)) {
  case Remote.First:
  case 2:
}
function generic<T extends Fruit>(value: T): void {
  value === 0;
  const local = Fruit.Banana;
  local === 1;
}
