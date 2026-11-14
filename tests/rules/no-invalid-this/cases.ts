// Reported: a module is strict, and these functions are called without a `this`.
console.log(this);
function plain() {
  return this;
}
const arrow = () => this;
const expression = function () {
  return this;
};
function outer() {
  return () => this;
}
// Not reported.
function Constructor(this: any) {
  this.x = 1;
}
function withThis(this: { a: number }) {
  return this.a;
}
const Upper = function () {
  return this;
};
const obj = {
  method() {
    return this;
  },
  property: function () {
    return this;
  },
};
class C {
  field = this;
  arrow = () => this;
  static {
    console.log(this);
  }
  method() {
    return this;
  }
}
[1].map(function () {
  return this;
}, {});
const bound = function () {
  return this;
}.bind({});
/** @this {Object} */
function documented() {
  return this;
}
export { plain, arrow, expression, outer, Constructor, withThis, Upper, obj, C, bound, documented };

// TypeScript wrappers do not change the binding (10.15.0).
type Foo = () => unknown;
declare const holder: { foo: Foo };
declare const pick: Foo | undefined;
holder.foo = function () { return this; } as Foo;
holder.foo = <Foo>function () { return this; };
holder.foo = function () { return this; } satisfies Foo;
holder.foo = function () { return this; }!;
holder.foo = function <T>() { return this; }<string>;
holder.foo = (pick || function () { return this; }) as Foo;
holder.foo = (() => function () { return this; } as Foo)();
holder.foo = (function () { return function () { return this; }; } as any)();
holder.foo = ((() => function () { return this; }) satisfies () => Foo)();
holder.foo = (function () { return function () { return this; }; })!();
(holder.foo as Foo) = function () { return this; };
holder.foo! = function () { return this; };
(function () { return this; } as Foo).call(holder);
[].forEach(function () { return this; } as Foo, holder);
// Still the default binding: the `thisArg` is null or undefined behind a wrapper.
(function () { return this; }).call(undefined!);
Reflect.apply(function () { return this; }, <any>null, []);
Array.from([], function () { return this; }, null satisfies any);
[].forEach(function () { return this; }, null as any);
// A name whose first code point (not UTF-16 unit) is upper case is a constructor.
function 𐐀() { return this; }
function 𐐨() { return this; }

// A `this` as the default value of a parameter is a ThisExpression (not the `this` parameter).
export function defaultThis(value = this) {
	return value;
}
export const arrowDefaultThis = (value = this) => value;
export function typedDefaultThis(this: unknown, value = this) {
	return value;
}
