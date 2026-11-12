// non-nullable-type-assertion-style: the fix replaces the assertion with `expression!`, wrapping
// the expression in parentheses unless it binds tighter than a unary operator.
// Non-ASCII text before the ranges: ñ 😀 日本語.
declare const maybe: string | undefined;
declare const cond: boolean;
declare const obj: { a?: string; f(): string | null; ['k']: string | null };
declare const maybeObj: { a: string } | undefined;
declare const promise: Promise<string | undefined>;
declare function tag(strings: TemplateStringsArray): string | null;
declare let slot: string | undefined;

// Primary, member, call: no parentheses.
const a1 = maybe as string;
const a2 = <string>maybe;
const a3 = obj.a as string;
const a4 = obj['k'] as string;
const a5 = obj.f() as string;
const a6 = maybeObj?.a as string;
const a7 = tag`x` as string;
// Parentheses around the expression are not part of it.
const b1 = (maybe) as string;
const b2 = ((maybe)) as string;
const b3 = <string>(maybe);
const b4 = (obj.f()) as string;
// Unary precedence or lower: parentheses.
const c1 = (maybe ?? undefined) as string;
const c2 = (cond ? maybe : undefined) as string;
const c3 = (cond && maybe || undefined) as string;
const c4 = (maybe as string | undefined) as string;
const c5 = (<string | undefined>maybe) as string;
const c6 = (maybe satisfies string | undefined) as string;
const c7 = (slot = maybe) as string;
const c8 = (cond, maybe) as string;
const c9 = <string>(maybe ?? undefined);
const c10 = <string>(maybe as string | undefined);
async function awaited() {
  const d1 = (await promise) as string;
  const d2 = <string>await promise;
  return [d1, d2];
}
function* yielded(): Generator<number, void, string | undefined> {
  const e1 = (yield 1) as string;
  void e1;
}
// Comments and several lines.
const f1 = maybe /* before */ as /* after */ string;
const f2 = obj
  .f() as
  string;
const f3 = (
  // the expression
  maybe ?? undefined
) as string;
const f4 = <string>/* between */ maybe;
// Non-ASCII text on the same line.
const ñ = '😀'; const g1 = maybe as string; const 日本 = '語'; const g2 = (cond ? maybe : undefined) as string;
// Nested assertions: each one has its own fix.
type Loose = { a?: string };
declare const maybeLoose: Loose | undefined;
const h1 = (maybeLoose as Loose).a as string;
const h2 = <string>(<Loose>maybeLoose).a;
class Holder {
  value?: string;
  get(): string {
    return this.value as string;
  }
}
