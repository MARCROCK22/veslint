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

// eslint-plugin-unicorn 79.0.0: a boolean constant in one branch and a boolean in the other is
// reported, without a fix in a TypeScript file.
declare const p: boolean, q: boolean, s: string, n: number;
declare function yes(): true;
declare function pred(x: unknown): boolean;
const b1 = p ? true : q;
const b2 = p ? q : false;
const b3 = s ? false : q;
const b4 = a === b ? true : c === 1;
const b5 = s ? true : s.startsWith('x');
const b6 = s ? true : pred(s);
const b7 = s ? Boolean(a) : false;
const b8 = s ? true : Array.isArray(a);
const b9 = s ? true : new Set<number>().has(1);
const b10 = s ? true : /x/.test(s);
const b11 = s ? true : /x/g.global;
const b12 = p ? true : (a as boolean);
const b13 = p ? true : !q;
function bf1(): boolean {
  return p;
}
const b14 = s ? true : bf1();
const isOk = (value: number) => value > 1;
const b15 = s ? isOk(1) : false;
const t1 = true;
const b16 = s ? t1 : q;
const b17 = s ? (true as const) : q;
const b18 = s /* keep */ ? true : q;
const b19 = s ? true : a === b && c === 1;
/** @param {boolean} flag */
function bj(flag) {
  return s ? true : flag;
}
// Not reported: the other branch may not be a boolean, or both branches are constants.
const nb1 = p ? true : s;
const nb2 = p ? true : a;
const nb3 = p ? true : false;
const nb4 = p ? t1 : false;
const nb5 = p ? true : n;
const nb6 = p ? (true as boolean) : q;
const nb7 = s ? yes() : q;
const nb8 = s ? true : a.b;

// `a == null ? b : a` suggests `a ?? b`; `a == null ? undefined : a.b` suggests `a?.b`.
const n1 = a == null ? b : a;
const n2 = a != undefined ? a : b;
const n3 = a === null || a === undefined ? b : a;
const n4 = a !== null && undefined !== a ? a : b;
const n5 = a == null ? undefined : a.b;
const n6 = a != null ? a[b] : undefined;
const n7 = a == null ? undefined : (a as any).b;
const n8 = a?.b == null ? undefined : a.b;
const n9 = a == null ? /* keep */ undefined : a.b;
const n10 = a == null ? undefined : a /* keep */ .b;
function nf1() {
  return(a) == null ? undefined : a.b;
}
async function nf2() {
  return await((a) == null ? undefined : a.b);
}
for (const item of(a) == null ? undefined : a.items);
// Not reported: an optional chain would change what is deleted, called or tagged.
delete (a == null ? undefined : a.b);
(a == null ? undefined : a.b)();
(a == null ? undefined : a.b)`tag`;
const nn1 = a === null ? b : a;
const nn2 = a == null ? a : b;
const nn3 = a === null || b === undefined ? c : a;

// Comments outside the operands keep the suggestions away.
const cm1 = a ? a /* keep */ : b;
const cm2 = (/* keep */ a) ? a : b;
// Static strings compare by value.
const ss1 = a['x'] ? a[`x`] : b;
// Parentheses for a statement that would start with `{`.
!{ value: null }.value ? 1 : { value: null }.value;
