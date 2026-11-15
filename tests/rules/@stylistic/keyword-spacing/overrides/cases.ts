declare const a: any;
declare function foo(...args: unknown[]): any;
if (a) {} else {}
if(a){}else{}
if (a) {}else if (a) {}
const x = (a) as any;
const x2 = (a)as any;
const y = [a] satisfies unknown[];
const fn = [function () {}, (function(){})];
const t = [this];
const u = (this);
try {} catch {}
try {} catch(e) {}
class C { static [a] = 1; static{} get [a]() { return 1 } get[a]() { return 1 } async [a]() {} async[a]() {} }
const o = { async [a]() {}, async*[a]() {} };
async function g() { for await (const k of [a]) {} for (const k of(a)) {} return (await a); }
{ using u = foo(); }
const f2 = async () => 1;
const f3 = (async () => 1);
