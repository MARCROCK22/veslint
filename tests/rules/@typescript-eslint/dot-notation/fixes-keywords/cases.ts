// dot-notation with allowKeywords false: the fix of `useBrackets` (and `useDot` leaves keywords).
// Non-ASCII text before the ranges: ñ 😀 日本語.
declare const a: any;

// The dot goes and the name becomes a string between brackets.
a.class;
a.if.else;
a.null;
a.true.b;
a.new();
a.default = 1;
// `?.` stays.
a?.class;
a?.b.class;
a.b?.delete;
// Parentheses, spaces and several lines.
(a).class;
a . class;
a
  .class;
a.
  class;
// A comment between the dot and the name: no fix. Before the dot, it stays.
a./* between */class;
a. // between
  class;
a /* before */ .class /* after */;
// Keywords between brackets are not reported.
a['class'];
a['b'];
// Non-ASCII text on the same line.
const ñ = '😀'; a.class; const 日本 = a?.typeof;
