declare const a: any;
if (a) {} else {}
if(a){}else{}
try {} catch (e) {} finally {}
const x = (a) as (any);
const y = [a] satisfies [any];
for (const k of [a]) {}
function f() { return [1]; }
const t = a > this;
const s = `${a}` in a;
const r = /x/ instanceof RegExp;
class C { #p = 1; m() { return #p in this; } }
