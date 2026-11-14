// prefer-optional-chain: the fix and the suggestions. Non-ASCII text before the ranges: ñ 😀 日本語.
type Deep = { bar?: { baz?: { qux(): number; list: number[] } }; fn?: <T>(x?: T) => T; 'a-b'?: Deep };
type Strict = { bar: { baz: { qux: number } } };
declare const strict: Strict | null;
declare const strictHolder: { inner: Strict | null };
declare const und: Deep | undefined;
declare const nul: Deep | null;
declare const both: Deep | null | undefined;
declare const anyValue: any;
declare const key: 'bar';
declare const cond: boolean;
declare const maybeFn: (() => Deep) | undefined;
declare function later(): Promise<Deep | undefined>;
class Holder {
  #inner?: { value?: { deep: number } };
  field?: { value?: { deep: number } };
  read(): unknown {
    return [this.#inner && this.#inner.value, this.field && this.field.value && this.field.value.deep];
  }
}

// A fix when an operand includes undefined, a suggestion when none does.
und && und.bar;
nul && nul.bar;
both && both.bar;
anyValue && anyValue.bar;
nul && nul.bar && nul.bar.baz;
// No operand includes undefined: the fix would change the type, so it is only suggested.
strict && strict.bar;
strict && strict.bar && strict.bar.baz;
strict != null && strict.bar;
strict !== null && strict.bar.baz.qux;
!strict || strict.bar.baz;
strictHolder.inner && strictHolder.inner.bar.baz;
// The comparison type of the last operand also allows the fix.
strict != null && strict.bar != null;
!strict || !strict.bar;
nul != null && nul.bar != null;
nul !== null && nul !== undefined && nul.bar !== undefined;
nul != null && nul.bar !== undefined;
!nul || !nul.bar;
nul == null || nul.bar == null;
nul != null && nul.bar === undefined;

// What each operand adds: members, computed members, calls, type arguments, `!`, an existing `?.`.
und && und.bar && und.bar.baz && und.bar.baz.qux();
und && und['bar'] && und['bar'].baz;
und && und[key];
und && und['a-b'] && und['a-b']['a-b'];
maybeFn && maybeFn();
maybeFn && maybeFn().bar;
und && und.fn && und.fn<string>('x');
und && und.fn && und.fn /* c */ <string> /* d */ ( /* e */ 'x' /* f */ );
und && und.bar && und.bar.baz && und.bar.baz.list[0];
und && und.bar!.baz;
und! && und!.bar;
und && und.bar && und.bar!.baz && und.bar!.baz!.list;
und?.bar && und.bar.baz;
und?.bar && und?.bar.baz && und.bar.baz.qux;
(und) && (und).bar;
und && (und.bar) && (und.bar.baz);

// The base expression in parentheses when it needs them.
async function bases() {
  (await later()) && (await later())!.bar;
  (und as Deep | undefined) && (und as Deep).bar;
  return (cond ? und : nul) && (cond ? und : nul)!.bar;
}

// The last comparison stays, also with typeof and written backwards.
und && und.bar != null;
und && und.bar !== undefined;
und && typeof und.bar !== 'undefined';
und && null != und.bar;
und && 'undefined' !== typeof und.bar;
und != null && und.bar === undefined;
und != null && typeof und.bar === 'object';
und != null && undefined === und.bar;
und == null || und.bar == null;
und == null || und.bar !== undefined;
!und || und.bar === undefined;
!und || !und.bar || !und.bar.baz;

// The report range takes the parentheses around its ends.
(und && und.bar);
((und) && (und.bar));
cond && (und && und.bar && und.bar.baz);
(und && und.bar) && und.bar.baz;
cond || (und && und.bar);
const inArguments = [(und && und.bar), !(und && und.bar && und.bar.baz)];
// A `(` of the range that closes after it: the whole expression is replaced.
(und && und.bar && cond) && anyValue;
((und && und.bar) && cond && anyValue);
// Several lines and comments.
und &&
  und.bar &&
  // the last one
  und.bar.baz;
und /* a */ && /* b */ und.bar /* c */ && und.bar /* d */ .baz;

// `(x || {}).y` and `(x ?? {}).y`: always a suggestion.
(und || {}).bar;
(und ?? {}).bar;
(und || {})[key];
(und || {})['a-b'];
(und!.bar || {}).baz;
(und && und.bar || {}).baz;
(maybeFn! () || {}).bar;
(und! || {}).bar;
(und as Deep || {}).bar;
((und) || ({})).bar;
(und || {}).bar!.baz;
async function awaitedBase() {
  return (await later() || {}).bar;
}

// Non-ASCII text on the same line.
const ñ = '😀'; und && und.bar; const 日本 = (und || {}).bar; const 語 = (und && und.bar && cond) && ñ;
// typescript-eslint 8.72: a chain with a last operand is only a suggestion; in an OR chain with a
// `=== undefined` guard a lone `=== null` ends the chain; a generic or void last value may be
// undefined.
declare const g1: { a?: { b: number | null } } | undefined;
const l1 = g1 && g1.a && g1.a.b !== undefined;
const l2 = g1 === undefined || g1.a === null;
const l3 = g1 == null || g1.a === undefined || g1.a.b === null;
const l4 = g1 === null || g1 === undefined || g1.a === null;
function genericLast<T>(x: { y?: { z: T } }) {
  return x.y && x.y.z !== undefined;
}
declare const v1: { y?: { z: void } };
const l5 = v1.y && v1.y.z !== undefined;
void [l1, l2, l3, l4, l5, genericLast];
