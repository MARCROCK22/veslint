declare const a: any;
declare function foo(...args: unknown[]): any;

function f1() {}
function f2() {}
function f3()  {}
function f4()/* c */ {}
function f5()
{}
const f6 = function() {};
const f7 = () => {};
const f8 = async()=> {};
if (a) {} else {}
if (a) {} else {}
for (;;) { break }
while (a) {}
do {} while (a);
try {} catch(e) {} finally {}
try {} catch {}
switch (a) { case 1: { break } default: {} }
switch (a)  {}
switch (a) {}
label: {}
{ {} }
class C1 {}
class C2 extends C1 { m() {} static {} }
const C3 = class {};
enum E1 { A }
enum E2 { B }
interface I1 {}
interface I2 extends I1 {}
namespace N1 {}
namespace N2.N3 {}
declare module 'm1' {}
declare global {}
const o = { m() {}, get g() { return 1 }, set s(v: number) {} };
function f9(): void {}
function f10(x: number): x is 1 { return true }
const f11 = (): void => {};
type T = { a: 1 };
