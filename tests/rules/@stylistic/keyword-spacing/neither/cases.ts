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
