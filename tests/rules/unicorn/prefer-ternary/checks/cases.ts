// unicorn/prefer-ternary with checkVaryingBase and checkComputedMemberAccess: calls and member
// reads that differ by their callee, receiver or static property name are minimal ternaries too.
declare let test: boolean, value: number;
declare let a: { method(value: number): void; value: number }, b: { method(value: number): void; value: number };
declare let object: { a(value: number): void; b(value: number): void; x: number; y: number };
declare function f(value: number): void;
declare function g(value: number): void;

if (test) { f(value); } else { g(value); }
if (test) { a.method(value); } else { b.method(value); }
if (test) { a.value; } else { b.value; }
async function m1(first: () => Promise<void>, second: () => Promise<void>) {
  if (test) { await first(); } else { await second(); }
}
if (test) { object.a(value); } else { object.b(value); }
if (test) { object.x; } else { object.y; }
const enum First { value }
const enum Second { value }
if (test) { First.value; } else { Second.value; }
// Not reported: different arguments too.
if (test) { f(1); } else { g(2); }
