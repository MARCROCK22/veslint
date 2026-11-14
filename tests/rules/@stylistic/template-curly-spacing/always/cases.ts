declare const foo: string;
declare const bar: number;
declare function tag(strings: TemplateStringsArray, ...values: unknown[]): string;

const a = `${foo} and ${ bar }`;
const b = `${ foo } and ${bar}`;
const c = tag`${foo}${bar}`;
const d = `${
	foo
} and ${/* c */ bar /* d */}`;
const e = `héllo ñ ${foo} ü ${bar}`;
const f = `outer ${`inner ${foo}`} end`;
type G = `prefix-${string}-suffix`;
type H = `${ number }px`;
const i = `${ foo }${ bar }`;
const j = `no substitutions`;
const k = `${// comment
	foo}`;
const l = `${ foo /* x */}`;

export { a, b, c, d, e, f, i, j, k, l };
export type { G, H };
