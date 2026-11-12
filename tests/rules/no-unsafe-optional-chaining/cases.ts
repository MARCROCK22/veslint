declare const obj: any;
declare const arr: any[] | undefined;
declare function f(...args: unknown[]): any;

// Reported: the chain's `undefined` reaches a place that throws.
(obj?.foo).bar;
(obj?.foo)[0];
(obj?.foo)();
new (obj?.foo)();
(obj?.foo)`tpl`;
[...obj?.items];
f(...obj?.args);
const { a } = obj?.foo;
const [b] = obj?.list;
let c: any;
({ c } = obj?.foo);
[c] = obj?.list;
for (const item of obj?.items) {}
'key' in obj?.foo;
obj instanceof obj?.Ctor;
class A extends obj?.Base {}
const B = class extends (obj?.Base) {};
function g({ x } = obj?.foo) {}
const h = ([y] = obj?.list) => y;
const [{ z } = obj?.foo] = [];
const { p: { q } = obj?.foo } = {} as any;
(obj?.foo || obj?.bar).baz;
(obj?.foo ?? obj?.bar).baz;
(obj?.foo && obj?.bar).baz;
(obj ? obj?.foo : obj?.bar).baz;
(f(), obj?.foo).bar;
async function k() {
  (await obj?.foo).bar;
}
(obj?.foo!).bar;
(obj?.foo?.bar).baz;
(obj?.foo.bar).baz;
(obj?.foo()).bar;

// Not reported.
obj?.foo.bar;
obj?.foo?.();
obj?.foo();
(obj?.foo)?.bar;
({ ...obj?.foo });
(obj?.foo || {}).bar;
(obj?.foo as any).bar;
const { d } = obj?.foo ?? {};
for (const key in obj?.foo) {}
obj?.foo + 1;
-obj?.foo;
let e = 1;
e += obj?.foo;
