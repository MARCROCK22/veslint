declare function tag(strings: TemplateStringsArray, ...values: unknown[]): string;
declare function generic<T>(strings: TemplateStringsArray, ...values: T[]): string;
declare const obj: { tag: typeof tag };
declare const name: string;

const a = tag `name`;
const b = tag`name`;
const c = tag   `hello ${name}`;
const d = obj.tag `x`;
const e = (tag) `x`;
const f = generic<string> `x ${name}`;
const g = generic<string>`x`;
const h = tag /* block */ `x`;
const i = tag/* one */ /* two */`x`;
const j = tag // line
`x`;
const k = tag
`x`;
const l = `outer ${tag `inner`}`;
const m = tag `ñü ${tag `é`}`;

export { a, b, c, d, e, f, g, h, i, j, k, l, m };
