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
// 6.0.0: `for await` is checked as `for`, comments next to a keyword are kept
async function forAwait6(list: string[], b: boolean) {
  for await(const k of list) {}
  {}for await (const k of list) {}
  {} for  await(const k of list) {}
  for/* c */await(const k of list) {}
  for await  (const k of list) {}
  if (b) {} /* comment */ else{}
  if (b) {}else /* comment */ {}
  if (b) {} /*)*/ else {}
  if (b) {} else /*(*/ {}
  if (b) {} else //(
  {}
  const cl1 = (class{});
  const cl2 = (class {});
  const cl3 = (class  {});
  return [cl1, cl2, cl3];
}
