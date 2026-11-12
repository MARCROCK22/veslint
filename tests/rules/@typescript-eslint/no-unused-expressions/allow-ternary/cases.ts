'use strict';
"directive two";
('parenthesized string');
'after the parenthesized one';
// no-unused-expressions: an expression statement without side effects (not a call, an
// assignment, `new`, `await`, `yield`, `delete`, `void`, an update…), but directives.
declare let a: any, b: any, c: any, d: any, e: any, f: any, g: any, i: any, foo: any, obj: any;
declare let tag: any, func: any, one: any, test: any, C: any;
// Cases borrowed from ESLint 10.6.0's tests of the core rule:
function f1(){}
a = b
new a
{}
f(); g()
i++
a()
a && a()
a() || (b = c)
a ? b() : c()
a ? b() || (c = d) : e()
delete foo.bar
void new C
var foo1 = () => {"use strict"; return true; }
function* foo2(){ yield 0; }
async function foo3() { await 5; }
async function foo4() { await foo.bar; }
async function foo5() { bar && await baz; }
async function foo6() { foo ? await bar : await baz; }
tag`tagged template literal`
shouldNotBeAffectedByAllowTemplateTagsOption()
import("foo")
func?.("foo")
obj?.foo("bar")
function foo7() {"use strict"; return true; }
function foo8() {"directive one"; "directive two"; f(); }
0
a
f(), 0
{0}
;[]
a && b();
a() || false
a || (b = c)
a ? b() || (c = d) : e
`untagged template literal`
a || b
a() && b
a ? b : 0
a ? b : c()
foo.bar;
!a
+a
function foo9() {"directive one"; f(); "directive two"; }
if (0) { "not a directive"; f(); }
function foo10() { var foo = true; "use strict"; }
var foo11 = () => { var foo = true; "use strict"; }
obj?.foo
obj?.foo.bar
obj?.foo().bar
class C1 { static { 'use strict'; } }
class C2 { static {
'foo'
'bar'
} }
foo;
// typescript-eslint's own cases (more in upstream.json):
test.age?.toLocaleString();
one[2]?.[3][4]?.();
a?.['b']?.c();
(a?.b).c;
a?.b()?.c;
(a?.b()).c;
one.two?.three.four;
class Foo<T> {}
new Foo<string>();
Foo<string>;
Map<string, string>;
foo as any;
<any>foo;
foo!;
// More: every ESTree type the core rule knows, and TypeScript expressions.
[1, 2];
() => {};
(function () {});
(function* () {});
(class {});
1 + 2;
a in b;
a instanceof b;
a ?? b;
a?.b!;
a?.()!;
(a?.b)!;
a?.[0];
super_();
typeof a;
-a;
~a;
void a;
delete a.b;
a++;
--a;
a += 1;
a ||= b;
a ??= b;
`template ${a}`;
/regex/;
null;
true;
undefined;
10n;
this;
({});
(a, b);
a satisfies unknown;
a as const;
(a as any)!;
<string>(a as any);
a<string>;
a!<string>;
new.target;
import.meta;
await a;
a ? b : c;
(a);
((a()));
label: a;
if (a) b; else c;
while (a) b;
for (a; b; c) d;
for (const x of a) x;
switch (a) { case 1: b; }
try { a; } catch { b; } finally { c; }
function super_() {}
function directives() {
  'use strict';
  ('parenthesized');
  'not a directive any more';
}
const arrow = () => {
  'use strict';
  "second";
  a;
};
class Methods {
  method() {
    'use strict';
    a;
  }
  get g() {
    'use strict';
    return 1;
  }
  constructor() {
    'use strict';
  }
  static {
    'in a static block';
    ('parenthesized in a static block');
  }
}
namespace NS {
  'use strict';
  a;
}
module M {
  'use strict';
}
declare global {
  'not quite';
}
declare module 'mod' {
  'in a module';
}
{
  'in a block';
}
if (a) {
  'in an if';
}
