let x = 1;;
;
function f() {
  ;'use strict';
  return 1;;
};
for (;;);
while (x--);
do ; while (x);
if (x);
else;
label: ;
for (const k in {});
for (const k of []);
export class A {
  ;
  a = 1;;
  ;b = 2
  m() {};
  ;;
  static {};
  get g() { return 1; };
  accessor acc = 1;;
  [k: string]: unknown;;
  ;[key] = 3;
  n() {}; @dec o() {}
}
export abstract class B {
  abstract m(): void;;
  abstract p: number;;
}
declare function dec(...args: unknown[]): void;
declare const key: string;
const C = class { m() {};; };
{ ; }
switch (x) { case 1: ; }
;'not a directive';
function g() { if (x) { ;'block'; } }
const h = () => { ;'arrow'; };
/* a */ ; /* b */
x++; ;
export { f, C, g, h };
