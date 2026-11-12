declare let a: any;
declare let b: any;
declare function f(): any;

// Reported: constant short circuits.
const s1 = [] && a;
const s2 = true || a;
const s3 = !a || ({} && b);
const s4 = (a = 1) && b;
const s5 = {} ?? a;
const s6 = `x` ?? a;
const s7 = (a + 1) ?? b;
const s8 = new Date() ?? a;
const s9 = String(a) ?? b;
const s10 = (a ??= 1) || b;
const s11 = void a ?? b;

// Reported: comparisons whose result never changes.
const c1 = a + 1 == null;
const c2 = null === {};
const c3 = undefined == [];
const c4 = `x` !== undefined;
const c5 = true == [];
const c6 = !a === 'x';
const c7 = Boolean(1) == [a, b];
const c8 = false === a + 1;
const c9 = true !== String(a);
const c10 = void 0 == (() => {});
const c11 = (a, null) == {};

// Reported: comparisons with a new object.
const n1 = a === {};
const n2 = [] !== a;
const n3 = a === new Map();
const n4 = a === /re/;
const n5 = a === (b ? [] : {});
const n6 = [] == {};
const n7 = a === (b = []);

// Not reported.
const k1 = a && b;
const k2 = a ?? b;
const k3 = a === b;
const k4 = a == null;
const k5 = true === a;
const k6 = a === new Foo();
const k7 = f() ?? a;
const k8 = (a ||= 1) ?? b;
const k9 = 1 < 2;
const k10 = a === Boolean?.(1);
const k11 = (a as any) === {} as any;
const k12 = [...a] == true;
class Foo {}
function shadow(undefined: unknown, String: (x: unknown) => string) {
  const x = undefined == {};
  const y = String(1) ?? a;
}
