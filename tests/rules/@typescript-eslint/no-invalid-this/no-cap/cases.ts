function Ctor() { this.x = 1; }
function Ctor2(this: object) { this; }
const Foo = function () { return this; };
class C { p = function Bar() { return this; }; }
export { Ctor, Ctor2, Foo, C };
