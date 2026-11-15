declare class Foo { constructor(...args: unknown[]); bar: typeof Foo; }
declare const ns: { Foo: typeof Foo };
export const a = new Foo;
export const b = new Foo();
export const c = new Foo(1, 2);
export const d = new ns.Foo;
export const e = new ns.Foo();
export const f = new (Foo);
export const g = new (Foo)();
export const h = (new Foo);
export const i = (new Foo)();
export const j = new Foo<string>;
export const k = new Foo<string>();
export const l = new Foo ( );
export const m = new Foo /* c */ ( /* d */ );
export const n = new (new Foo().bar);
export const o = new (new Foo().bar)();
export const p = new Foo
();
export const q = [new Foo, new Foo()];
export const r = new class {};
export const s = new class {}();
export const t = new Foo()();
export const u = new (ns.Foo)
