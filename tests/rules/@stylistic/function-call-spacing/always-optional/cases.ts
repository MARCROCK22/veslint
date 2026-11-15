declare const f: ((n?: number) => (n?: number) => number) & { g?: () => number; h: <T>(v?: T) => T };
declare const o: { m?: (n?: number) => number } | undefined;
declare class Foo { constructor(v?: number) }

f();
f ();
f  ();
f
();
f/* c */();
f /* c */ ();
f // c
();
f()();
f() ();
(f)();
(f) ();
f.h<string>();
f.h<string> ();
f.h <string>();
f?.();
f ?.();
f?. ();
f ?. ();
f?.
();
o?.m?.();
o?.m ?.(1);
o?.m?.  (1);
f.g?.();
f.g ?.
  ();
f?./* c */();
new Foo();
new Foo ();
new Foo;
new (Foo);
new (Foo) ();
new Foo
(1);
export const imp = import('x'), imp2 = import ('x'), imp3 = import
('x'), imp4 = import/* c */('y');
f(f ());
f	();
export const tagged = String.raw`a`;
f ();
f?. ();
f ?.();
f /* é */ ();
f /*
*/ ();
f?.	
 ();
