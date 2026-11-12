// no-non-null-asserted-nullish-coalescing: a `!` on the left of `??`. On a variable it is reported
// only when the variable may have a value there: a write before the end of the `!`, or a
// declaration with an initializer or a definite assignment before it.
declare const foo: string | undefined;
declare const obj: { bazz?: string };
declare function call(): string | undefined;

foo! ?? 'a';
obj.bazz! ?? 'b';
obj!.bazz! ?? 'c';
call()! ?? 'd';
(foo!) ?? 'e';
foo!! ?? 'f';
(obj?.bazz)! ?? 'g';
foo /* comment */ ! ?? 'h';
foo  ! ?? 'i';
this! ?? 'j';
undefined! ?? 'k';
missingGlobal! ?? 'l';

// Not the left of `??`, or a `!` inside an optional chain (a ChainExpression).
'a' ?? foo!;
(foo ?? 'b')!;
foo! || 'c';
obj?.bazz! ?? 'd';
obj?.bazz!.length ?? 'e';

// Variables.
let v1: string;
v1! ?? 'no assignment yet';
let v2 = call();
v2! ?? 'initialized';
let v3!: string;
v3! ?? 'definite';
let v4: string;
v4 = 'x';
v4! ?? 'assigned before';
let v5: string;
v5! ?? 'assigned after';
v5 = 'x';
v6! ?? 'declared after';
var v6 = 'x';
function f1(p1?: string, p2 = 'x', ...p3: string[]) {
  return [p1! ?? '', p2! ?? '', p3! ?? []];
}
function f2() {
  return [v1! ?? '', v2! ?? ''];
}
for (const k of ['a']) {
  k! ?? '';
}
for (let i = 0; i < 1; i++) {
  i! ?? 0;
}
try {
  call();
} catch (e) {
  e! ?? '';
}
class K {}
K! ?? 1;
function f3() {}
f3! ?? 1;
let v7: string | undefined;
[v7] = ['x'];
v7! ?? '';
let v8: string | undefined;
({ v8 } = { v8: 'x' });
v8! ?? '';
let v9: number | undefined;
v9++;
v9! ?? 0;
let v10: string | undefined;
v10 ??= 'x';
v10! ?? '';
let v11: string | undefined;
const v12 = v11! ?? (v11 = 'x');
let v13 = (v13! ?? 0) as number;

export { v12, v13, f1, f2 };
