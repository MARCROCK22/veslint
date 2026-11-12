// prefer-nullish-coalescing: the suggestions. Non-ASCII text before the ranges: ñ 😀 日本語.
export {};
declare const s: string | undefined;
declare const n: number | null;
declare const o: { x?: string | null; y: { z?: number } } | undefined;
declare const rec: { a?: string };
declare const cond: boolean;
declare function f(): string | null;
declare function later(): Promise<string>;
declare let slot: string | undefined;

// `||` becomes `??`.
export const a1 = s || 'x';
export const a2 = (s) || ('x');
export const a3 = s /* a */ || /* b */ 'x';
export const a4 = s
  || 'x';
// Inside another `||` the new expression gets parentheses.
export const b1 = s || n || 'x';
export const b2 = cond || (s || 'x');
export const b3 = n || (cond && s || 'x');
export const b4 = s || n || o || 'x';
export const b5 = s || n || o || f() || 'x';
export const b6 = (s || n) || 'x';
// `||=` becomes `??=`.
slot ||= 'x';
o!.x ||= 'y';
cond || (slot ||= 'x');
slot /* a */ ||= /* b */ 'x';

// A conditional becomes `left ?? nullishBranch`.
export const t1 = s ? s : 'x';
export const t2 = !s ? 'x' : s;
export const t3 = s !== undefined ? s : 'x';
export const t4 = n === null ? 1 : n;
export const t5 = (s) ? (s) : ('x');
export const t6 = !(s) ? 'x' : s;
export const t7 = o?.y.z !== undefined ? o.y.z : 0;
export const t8 = rec.a ? rec.a : f();
export const t9 = s /* a */ ? /* b */ s /* c */ : /* d */ 'x' /* e */;
export const t10 = s
  ? s
  : 'x';
// The nullish branch gets parentheses unless it binds tighter than `??`.
export const p1 = s ? s : cond ? 'a' : 'b';
export const p2 = s ? s : n ?? 'x';
export const p3 = s ? s : cond || 'x';
export const p4 = s ? s : (cond, 'x');
export const p5 = s ? s : () => 'x';
export const p6 = s ? s : slot = 'x';
export const p7 = s ? s : 'a' + 'b';
export const p8 = s ? s : typeof cond;
export const p9 = s ? s : slot ||= 'x';
export const p10 = s ? s : (cond ? 'a' : 'b');
export const p11 = s ? s : cond == true;
export async function awaited() {
  return s ? s : await later();
}
export function* yielded(): Generator<number, void, string> {
  const y = s ? s : yield 1;
  void y;
}

// An `if` becomes `left ??= right;`, keeping the comments around the assignment.
export function ifs(v: string | undefined, ob: { x?: string | null }, key: 'x'): void {
  if (!v) v = 'x';
}
export function ifBlock(v: string | undefined): void {
  if (!v) {
    v = 'x';
  }
}
export function ifUndefined(v: string | undefined): void {
  if (v === undefined) v = 'x';
}
export function ifNull(v: string | null | undefined): void {
  if (v == null) {
    v = f() ?? 'x';
  }
}
export function ifComments(v: string | undefined): void {
  if (!v) /* before */ v = 'x'; /* after */
}
export function ifBlockComments(v: string | undefined): void {
  if (!v) {
    // before 1
    /* before 2 */ v = 'x'; // after 1
    /* after 2 */
  }
}
export function ifBlockCommentsNoSemicolon(v: string | undefined): void {
  if (!v) {
    /* before */ v = 'x' /* after 1 */
    // after 2
  }
}
export function ifMember(ob: { x?: string | null }): void {
  if (!ob.x) {
    ob.x = ('y');
  }
}
export function ifComputed(ob: { x?: string | null }, key: 'x'): void {
  if (ob[key] == undefined) ob[key] = 'a' + 'b';
}
export function ifParenthesizedLeft(v: string | undefined): void {
  if (!v) {
    (v) = 'x';
  }
}
export function ifNoSemicolon(v: string | undefined): void {
  if (!v)
    v = 'x'
}
export function ifParenthesizedAssignment(v: string | undefined): void {
  if (!v) (v = 'x');
}
export function ifRightForms(v: string | undefined): void {
  if (v === undefined) v = cond ? 'a' : 'b';
}
export function ifBeforeElse(v: string | undefined, w: string | undefined): void {
  if (cond) {
    if (!v) v = 'x';
  } else if (!w) w = 'y';
}

// Non-ASCII text on the same line.
export function nonAscii(ñ: string | undefined): void { const 日本 = '😀'; if (!ñ) ñ = '語'; void 日本; }
export const z = s || '語'; export const w = s ? s : '😀';
