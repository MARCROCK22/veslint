export {};
class Counter {
  count = 0;
  increment(): void {
    this.count++;
  }
  bound = (): void => {};
  field = function (this: Counter): void {};
  plainField = 1;
  static create(): Counter {
    return new Counter();
  }
  voidThis(this: void): void {}
  typedThis(this: Counter): void {}
  get value(): number {
    return this.count;
  }
}
interface Api {
  method(): void;
  voidMethod(this: void): void;
  property: () => void;
}
declare const counter: Counter;
declare const api: Api;
declare const maybe: Counter | undefined;
declare const condition: boolean;
const literal = {
  method() {},
  arrow: () => {},
  expression: function () {},
  voidExpression: function (this: void) {},
};

// Unbound methods.
const a1 = counter.increment;
const a2 = counter.field;
const a3 = Counter.create;
const a4 = counter.typedThis;
const a5 = api.method;
const a6 = literal.method;
const a7 = literal.expression;
const a8 = maybe?.increment;
const a9 = counter['increment'];
const a10 = (counter.increment);
const a11 = counter.increment!;
const a12 = counter.increment as () => void;
const a13 = [counter.increment];
counter.increment;
const a14 = condition ? counter.increment : undefined;
const a15 = condition || counter.increment;
const a16 = counter.increment satisfies unknown;
new counter.increment();
const a17 = `${counter.increment}`;

// Safe uses.
counter.increment();
counter.increment.bind(counter);
if (counter.increment) {
}
while (counter.increment) {
  break;
}
const s1 = typeof counter.increment;
const s2 = !counter.increment;
const s3 = counter.increment === undefined;
const s4 = counter.increment && 1;
const s5 = condition && counter.increment ? 1 : 2;
delete (counter as { increment?: unknown }).increment;
counter.increment = (): void => {};
const s6 = counter.voidThis;
const s7 = api.voidMethod;
const s8 = api.property;
const s9 = counter.bound;
const s10 = counter.plainField;
const s11 = counter.value;
const s12 = literal.arrow;
const s13 = literal.voidExpression;
counter.increment?.();
`${counter.increment}`;

// Natively bound globals.
const n1 = Math.max;
const n2 = JSON.parse;
const n3 = console.log;
const n4 = Object.keys;
const n5 = Array.isArray;
const n6 = Promise.resolve;
const n7 = Number.isNaN;
const n8 = String.raw;
const n9 = Date.now;
const n10 = [1].map;
const n11 = Symbol.for;

// Destructuring.
const { increment, bound, plainField } = counter;
const { increment: renamed } = counter;
const { log } = console;
const { max, min } = Math;
let target: () => void;
({ increment: target } = counter);
function withDefault({ increment: fromDefault } = counter): void {}
function fromParameter({ increment: fromParam }: Counter): void {}
const { method } = api;
const { [condition ? 'a' : 'b']: computed } = { a: 1, b: 2 };

class Child extends Counter {
  override increment(): void {
    this.increment = super.increment;
  }
}

// A local `Math` is not the global one.
function localMath(): void {
  const Math = {
    max(value: number): number {
      return value;
    },
  };
  const local = Math.max;
}
switch (counter.increment) {
  default:
}
for (counter.increment; condition; ) {
  break;
}
do {
  break;
} while (counter.increment);
