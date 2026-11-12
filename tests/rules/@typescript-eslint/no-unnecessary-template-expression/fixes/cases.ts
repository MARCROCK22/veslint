// no-unnecessary-template-expression: the fixes. Non-ASCII text before the ranges: ñ 😀 日本語.
declare const s: string;
declare const obj: { s: string };
type S = 'a' | 'b';

// A template that is only a string interpolation becomes the expression, in parentheses where
// the parent needs them.
const a1 = `${s}`;
const a2 = `${obj.s}`;
const a3 = `${s + s}`;
const a4 = `${s + s}`.length;
const a5 = `${s}`.length;
const a6 = !`${s + s}`;
const a7 = `${(s)}`;
const a8 = (`${s + s}`).length;
const a9 = `${obj?.s}`.length;
const a10 = `${s as string}`.length;
const a11 = `${`${s}`}`;
const a12 = `${s}` + `${s + s}`;
type T2 = `${S}`;
type T3 = `${string}`;
type T4 = `${'a' | 'b'}`;
type T5 = (`${S}`)[];

// Literals inside a longer template become their text.
const b1 = `a${'b'}c`;
const b2 = `a${"b`c"}d`;
const b3 = `a${'b${c}'}d`;
const b4 = `a${'b\`c'}d`;
const b5 = `a${'b\\`c'}d`;
const b6 = `a${1}b${1.50}c${0x10}d${1e21}e${10n}f${1_000}g${.5}`;
const b7 = `a${true}b${false}c${null}d`;
const b8 = `a${undefined}b${NaN}c${Infinity}d`;
const b9 = `a${/re\/x/gi}b${/a\\b/}c${/[/]/}d`;
const b10 = `a${'\\'}b${'\n'}c${'\''}d`;

// A `$` that would meet a `{`.
const c1 = `a${'$'}{b`;
const c2 = `a$${'{'}b`;
const c3 = `a${'$'}${'{'}b`;
const c4 = `a${`b$`}{c`;
const c5 = `a${`b$`}${'{'}c`;
const c6 = `a\$${'{'}b`;
const c7 = `a${'\\$'}{b`;
const c8 = `a${'\$'}{b`;
const c9 = `$${`{a`}`;
const c10 = `a$${`{b`}$${1}{c`;
const c11 = `a$${s}${'{'}b$${''}{c`;
const c12 = `a${'$'}${`{b${s}`}c`;

// Templates inside a template lose their backticks.
const d1 = `a${`b`}c`;
const d2 = `a${`b${s}c`}d`;
const d3 = `a${``}b${`${s}`}c`;

// Parentheses, spaces and several lines around the interpolation.
const e1 = `a${('b')}c`;
const e2 = `a${ 'b' }c`;
const e3 = `a${
  'b'
}c`;
const e4 = `a${((1))}b${ (`c`) }d`;

// Types.
type F1 = `a${'b'}c`;
type F2 = `a${1}b${true}c${null}d${undefined}e${1e3}f`;
type F3 = `a${`b`}c`;
type F4 = `a${'$'}{b`;
type F5 = `a$${'{'}b${S}`;
type F6 = `a${('b')}c${ 'd' }e`;

// Non-ASCII text on the same line.
const ñ = '😀'; const g1 = `ñ${'😀'}日本${s}${"語"}`; type G2 = `ñ${'😀'}語`;
