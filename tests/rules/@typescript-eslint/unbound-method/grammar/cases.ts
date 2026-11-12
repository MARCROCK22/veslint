// Type arguments without a call after a unary operator: the operand is the instantiation
// expression of the method, `!(box.method<string>)`.
class Box<T> {
  constructor(public value?: T) {}
  method<U>(): U | undefined { return undefined; }
  static of<U>(): Box<U> { return new Box<U>(); }
}
declare const box: Box<number>;
const negated = !box.method<string>;
const kind = typeof box.method<string>;
const ignored = void Box.of<string>;
const complement = ~box.method<number>;
const called = !box.method<string>();
async function awaited() {
  return [await box.method<string>, await Box.of<number>()];
}
export { negated, kind, ignored, complement, called, awaited };
