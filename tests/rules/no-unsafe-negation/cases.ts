declare const a: any;
declare const b: any;
declare const obj: object;
class Foo {
  #x = 1;
  has(o: object): boolean {
    return !(#x in o);
  }
}

// Reported: a negation on the left of `in` or `instanceof`.
if (!a in b) {}
if (!a instanceof Foo) {}
const c1 = !obj instanceof Foo;
const c2 = ! /* a comment */ a in b;
const c3 = !(a) in b;
const c4 = !!a in b;
const c5 = (!a in b) || (!a instanceof Foo);
const c6 = !a.b in b;
const c7 = !a in b in obj;

// Not reported: parenthesised, another operator, or not on the left.
if ((!a) in b) {}
if (!(a in b)) {}
if (a in !b) {}
if (!a < b) {}
if (!a >= b) {}
if (-a in b) {}
if (typeof a instanceof Foo) {}
const n1 = !(a instanceof Foo);
const n2 = ((!a)) instanceof Foo;
