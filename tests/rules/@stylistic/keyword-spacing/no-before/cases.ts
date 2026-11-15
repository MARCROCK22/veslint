declare const a: any;
declare function foo(...args: unknown[]): any;
if (a) {} else {}
if (a) {}else{}
try {} catch (e) {} finally {}
do {} while (a);
const x = (a) as any;
const y = [a] satisfies unknown[];
const z = { a } satisfies object;
const t = a>this;
const u = a> this;
const v = (a) instanceof Object;
const w = `${a}` in a;
class A {}
class B extends A {}
function* g() { yield [1]; }
async function f() { return [await a]; }
for (const k of [a]) {}
for (const k in {a}) {}
const fn = [async () => 1, function () {}];
const o = { get [a]() { return 1 }, async [a]() {} };
