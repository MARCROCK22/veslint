// unicorn/prefer-logical-operator-over-ternary: `a ? a : b` and `!a ? b : a` suggest `a ?? b` and
// `a || b`.
declare let a: any, b: any, c: any;
declare function f(): any;
declare class K {
  #p: any;
  m(): void;
}

// Reported, with the suggestions.
const x1 = a ? a : b;
const x2 = !a ? b : a;
const x3 = a.b ? a.b : c;
const x4 = a['b'] ? a.b : c;
const x5 = a[0] ? a[0] : b;
const x6 = a[1 + 1] ? a['2'] : b;
const x7 = a?.b ? a.b : c;
const x8 = (a as any) ? a! : b;
const x9 = (a) ? (a) : (b);
const x10 = a && b ? a && b : c;
const x11 = !a ? b : a || c;
const x12 = a ? a : b ? 1 : 2;
const x13 = a ? a : (b, c);
const x14 = a ? a : b = 1;
const x15 = a ? a : () => b;
const x16 = f() ? f() : b;
const x17 = 'x' ? 'x' : b;
const x18 = /re/g ? /re/g : b;
const x19 = 1n ? 1n : b;
async function g1() {
  return (await a) ? await a : b;
}
const x20 = typeof a ? typeof a : b;
class C {
  #p = 1;
  m() {
    return this.#p ? this.#p : this ? this : b;
  }
}
// A `;` keeps the logical expression from joining the statement before it.
let y = 1
;[a][0] ? [a][0] : b
f()
;(a) ? (a) : b

// Not reported.
const z1 = a ? b : a;
const z2 = a++ ? a++ : b;
const z3 = a.b ? a.c : c;
const z4 = /re/g ? /re/i : b;
const z5 = a ? b : c;
