declare const a: any;
declare function foo(...args: unknown[]): any;
if (a) {} else {}
if(a){}else{}
try {} catch (e) {} finally {}
try {} catch {}
do {} while (a);
switch (a) { case (1): break; default: }
const x = (a) as any;
const y = typeof (a);
const v = (a) instanceof Object;
for (const k of [a]) {}
for (const k in {a}) {}
function f() { return [1]; }
function g() { throw (a); }
const z = { get [a]() { return 1 }, async [a]() {} };
class C { static {} static [a] = 1; }
{ using u = foo(); }
const n = new (foo as any)();
