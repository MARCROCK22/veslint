// As in ../targets, with the element of a destructuring target in parentheses or with a type
// assertion: typescript-eslint's scope manager writes every identifier it finds there, also those
// of the type, so each `typeof x` makes `x` unknown. The grammar reads these targets as patterns.
declare const s: string;
let a = /a/;
let b = /b/;
let c = /c/;
let d = /d/;
let e = /e/;
let f = /f/;
let g = /g/;
let h = /h/;
let one: RegExp;
let two: RegExp;
[(one as typeof b)] = [/x/];
[one as typeof c] = [/x/];
({ k: (one as typeof d) } = { k: /x/ });
[<typeof e>one] = [/x/];
[one satisfies typeof f] = [/x/];
for ([(one as typeof g)] of [[/x/]]) {
}
[(one), two = (h)] = [/x/];
export const results = [
  s.match(a),
  s.match(b),
  s.match(c),
  s.match(d),
  s.match(e),
  s.match(f),
  s.match(g),
  s.match(h),
  one,
  two,
];
