declare const props: Record<string, string>;
declare function Comp<T>(props: { a?: T; b?: string; c?: string }): null;
export const a = <div id="a" className="b" />;
export const b = <div
  id="a" className="b" />;
export const c = <div id="a"
  className="b"
  title="c" />;
export const d = <div
  id="a"
  className="b"
/>;
export const e = <div {...props} id="a"
  title="t" />;
export const f = <Comp<string> a="x"
  b="y" />;
export const g = <Comp<string>
  a="x" b="y" />;
export const h = <svg xlink:href="#x"
  xml:lang="en" />;
export const i = <div id="a" /* comment */
  title="t" />;
export const j = <div
  id="a" /* comment */ title="t" />;
export const k = <div>
  <span id="a" title="t">text</span>
</div>;
export const l = <div {...{ a: 1,
  b: 2 }} id="x" />;
