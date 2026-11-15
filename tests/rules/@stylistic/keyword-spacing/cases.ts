declare const a: any;
declare const b: any;
declare function foo(...args: unknown[]): any;
declare function dec(...args: unknown[]): any;

// if / else
if(a){}else{}
if (a) {} else {}
if (a) {}else if(b) {}
if (a) {}
else {}

// loops
for(;;){ break }
while(a){ continue }
do{}while(a)
do {} while (a);
for(const k in a){}
for(const k of a){}
for (const k in(a)) {}
for (const k of[a]) {}
async function f1() {
  for await(const k of a) {}
  for await (const k of a) {}
  for await(const k of a){}
  await(a);
  const x = (await a)+1;
  return(await a);
}

// switch
switch(a){case(1): break; default: break}

// try
try{}catch(e){}finally{}
try {} catch {} finally {}
try{}catch{}

// throw / return / debugger
function f2() {
  if (a) throw(a);
  if (b) return[a];
  debugger
  return{a};
}

// declarations
const c1 = 1;
let c2={};
var c3=[1];
{
  using u1 = foo();
  await using u2 = foo();
}
function f3() { var v = (1); let w = [2]; const z = {}; return [v, w, z]; }

// classes
class A extends(foo()){}
class B extends A{}
const C = class extends(A){};
class D {
  static{ foo(); }
  static[a] = 1;
  static x = 1;
  static async*gen() {}
  get[a]() { return 1 }
  set[a](v: number) {}
  async[b]() {}
  accessor[a] = 1;
  static accessor y = 2;
  @dec static z = 1;
  public static w = 1;
  private static async m() {}
  #p = 1;
  m2() { return #p in this; }
}
const o = {
  get[a]() { return 1 },
  set[a](v: number) {},
  async[b]() {},
  async*[a]() {},
};

// functions
const f4 = async() => 1;
const f5 = async(x: number) => x;
const f6 = [function(){}, async function(){}];
const f7 = (async => async)(1);
function*g() { yield[1]; yield*[2]; yield(3); }

// expressions
const e1 = typeof(a);
const e2 = void(0);
const e3 = new(foo as any)();
const e4 = !this;
const e5 = a>this;
const e6 = a >this;
const e7 = [a] instanceof(foo);
const e8 = 'x' in(a);
const e9 = `${typeof a}`;
const e10 = `a${typeof a}b`;
const e11 = /re/.test(a)?typeof a:void 0;
const e12 = (a)as any;
const e13 = [a]as const;
const e14 = {a}satisfies object;
const e15 = a  as  any;
const e16 = (a)satisfies unknown;
class E extends A { m() { return super.m; } }
delete(a.b);
const e17 = "s"in a;
const e18 = a+typeof b;
const e19 = a-typeof b;
