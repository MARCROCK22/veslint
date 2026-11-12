// dot-notation: the fix of `useDot`. Non-ASCII text before the ranges: ñ 😀 日本語.
declare const a: any;
declare function tag(strings: TemplateStringsArray): void;

// The brackets become a dot and the name.
a['b'];
a["b"];
a[`b`];
a['b'].c;
a['b']['c'];
a['$dollar'];
a['_under'];
a['true'];
a[true];
a[null];
a['if'];
a['b'] = 1;
delete a['b'];
typeof a['b'];
// After `?.` there is no dot to add.
a?.['b'];
a?.['b']?.['c'];
a?.b['c'];
// Parentheses, spaces and several lines.
(a)['b'];
a[('b')];
a[ 'b' ];
a
  ['b'];
a[
  'b'
];
// A comment inside the brackets: no fix. Outside, it stays.
a[/* inside */ 'b'];
a['b' /* inside */];
a[
  // inside
  'b'
];
a /* outside */ ['b'] /* after */;
// After a decimal integer the dot needs a space.
5['toString'];
1_000['toString'];
0['toString'];
(5)['toString'];
5.5['toFixed'];
5n['toString'];
0x10['toString'];
5e3['toString'];
// A space after the name when the next token would join it.
a['b']in a;
a['b']instanceof Object;
a['b']as unknown;
a['b']+1;
a['b']`t`;
a['b']!;
a['b'].c;
a['b']/* comment */in a;
for (const k of a['b']in a ? [] : []) {
}
// Non-ASCII text on the same line.
const ñ = '😀'; a['b']; const 日本 = a?.['c']; a['語'];
