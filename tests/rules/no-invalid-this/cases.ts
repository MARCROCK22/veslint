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
