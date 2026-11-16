declare function foo(): void;
declare const a: number;
declare const b: number[];

{foo();}
{ foo();}
{foo(); }
{ foo(); }
{
foo();}
{foo();
}
if (a) {foo();} else {foo();}
if (a) {/* comment */ foo(); /* comment */}
if (a) {/* comment */foo();/* comment */}
if (a) { //comment
  foo();}
while (a) {foo();}
do {foo();} while (a);
for (;;) {foo();}
for (const x of b) {foo(); void x;}
for (const k in b) {foo(); void k;}
try {foo();} catch (e) {void e;} finally {foo();}
label: {foo(); break label;}
switch (a) {case 0: foo();}
switch (a) {}
switch (a) {  }
switch ({ a }.a) {case 1: break;}
switch (`${a}`) {default: foo();}
switch (a || {}) {case 0: foo();}
switch (a || { }) { case 0: foo(); }
switch (((a) || {})) {case 0: foo();}
switch (((a) || {b: 1})) {   }
switch (/* {c} */ x) {case 0: foo();}
function f1(): number {return 1;}
const f2 = (x: number): number => {return x;};
const f3 = function (): void {foo();};
class C1 {
  static {foo();}
  static { foo(); }
  static {}
  static { }
  method(): void {foo();}
  get value(): number {return a;}
  set value(v: number) {void v;}
}
abstract class C2 {
  abstract method(): void;
}
namespace N1 {export const x = 1;}
enum E1 {A, B}
interface I1 {x: number}
type T1 = {x: number};
const o1 = {x: 1};
void f1; void f2; void f3; void C1; void C2; void N1; void E1; void o1;
export type { I1, T1 };
{		foo();		}
{ /* a */ }
{/* a */}
{ // a
}
