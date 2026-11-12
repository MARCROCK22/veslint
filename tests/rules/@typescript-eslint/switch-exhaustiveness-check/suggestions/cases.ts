enum Fruit {
  Apple,
  Banana,
  Cherry,
}
enum Odd {
  'a-b' = 1,
  "it's" = 2,
  'é' = 3,
  '🎉' = 4,
  'new\nline' = 5,
  '' = 6,
  __under = 7,
  'a b' = 8,
  '1x' = 9,
  plain = 10,
  'back\\slash' = 11,
  'cr\rhere' = 12,
  '日本' = 13,
  'a‍b' = 14,
  $dollar = 15,
  'x·y' = 16,
  'ªb' = 17,
  '·x' = 18,
}
namespace NS {
  export enum Color {
    Red,
    'dark-blue',
  }
}
const enum Flag {
  On = 'on',
  Off = 'off',
}
declare const fruit: Fruit;
declare const odd: Odd;
declare const color: NS.Color;
declare const flag: Flag;
declare const letter: 'a' | 'b' | 'back\\slash' | "it's" | `tpl`;
declare const digit: -3 | 21 | 22 | 40n;
declare const truth: boolean;
declare const maybe: 'x' | null | undefined;
declare const symA: unique symbol;
declare const symB: unique symbol;
declare const sym: typeof symA | typeof symB;
declare const some: Fruit.Apple | Odd.plain | Odd['a-b'];
declare function run(): void;

switch (fruit) {
  case Fruit.Apple:
    break;
}
switch (fruit) {
  case Fruit.Apple:
    break;
  default:
    break;
}
switch (fruit) {
}
switch (fruit) { /* only a comment */ }
switch ((fruit)) {}
switch (fruit) {
  case Fruit.Apple:
    break;
  // no default
}
switch (fruit) {
  case Fruit.Apple:
    run() // trailing comment
}
switch (fruit) {
  case Fruit.Apple:
}
switch (fruit) { case Fruit.Apple: break; case Fruit.Banana: }
function nested(value: Fruit) {
  if (value) {
    switch (value) {
      case Fruit.Apple:
        return 1;
    }
  }
  if (value) switch (value) {}
  return 0;
}
function generic<T extends Fruit>(value: T) {
  switch (value) {
    case Fruit.Apple:
      break;
  }
}
switch (odd) {
  case Odd.plain:
    break;
}
switch (color) {
}
switch (flag) {
  case Flag.On:
    break;
}
switch (letter) {
  case 'a':
    break;
}
switch (digit) {
  case 21:
    break;
}
switch (truth) {
  case true:
    break;
}
switch (maybe) {
  case 'x':
    break;
}
switch (sym) {
  case symA:
    break;
}
switch (some) {
  case Fruit.Apple:
    break;
}
	switch (fruit) {
		case Fruit.Apple:
			break;
	}
/* 🎉é */ switch (fruit) { /* 🎉 */ case Fruit.Apple: break; }
label: switch (fruit) {
  case Fruit.Apple:
    break label;
  /* no default */
}
switch (fruit) {
  default:
}
switch (fruit) {
  // no default
}
enum __Weird {
  'a-b' = 1,
  '__x-y' = 2,
  __ok = 3,
}
declare const weird: __Weird;
declare const __symA: unique symbol;
declare const __symB: unique symbol;
declare const under: typeof __symA | typeof __symB;
class Holder {
  static readonly 'key-one': unique symbol;
  static readonly keyTwo: unique symbol;
}
declare const held: (typeof Holder)['key-one'] | typeof Holder.keyTwo;
declare const single: Odd.plain;
declare const lone: (typeof Holder)['key-one'];
switch (weird) {
}
switch (under) {
  case __symA:
    break;
}
switch (held) {
}
switch (single) {
}
switch (lone) {
}
void [nested, generic];
