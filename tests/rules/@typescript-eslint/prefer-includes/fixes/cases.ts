// prefer-includes: the fixes. Non-ASCII text before the ranges: ñ 😀 日本語.
declare const arr: number[];
declare const str: string;
declare const maybe: string[] | undefined;
declare const obj: { list: string[]; text: string; f(): string };
declare const cond: boolean;
declare function tag(strings: TemplateStringsArray): string;
const NOT_FOUND = -1;

// A positive check: the property becomes `includes` and the comparison goes.
arr.indexOf(1) !== -1;
arr.indexOf(1) != -1;
arr.indexOf(1) > -1;
arr.indexOf(1) >= 0;
// A negative check: `!` before the call.
arr.indexOf(1) === -1;
arr.indexOf(1) == -1;
arr.indexOf(1) <= -1;
arr.indexOf(1) < 0;
arr.indexOf(1) === NOT_FOUND;
// A string, a computed property, parentheses, comments and several lines.
str.indexOf('a') !== -1;
arr['indexOf'](1) !== -1;
(arr.indexOf(1)) !== -1;
(arr.indexOf(1)) === -1;
((arr).indexOf(1) !== -1);
arr.indexOf(1) !== (-1);
arr.indexOf(1) /* a */ !== /* b */ -1;
arr
  .indexOf(1)
  === -1;
if (arr.indexOf(1) === -1) {
}
const inLogical = cond && arr.indexOf(1) < 0;
const negated = !(arr.indexOf(1) === -1);
// An optional chain is reported without a fix.
maybe?.indexOf('a') !== -1;
obj.list?.indexOf('a') === -1;

// `/re/.test(x)`: only the argument stays, followed by `.includes('text')`.
/abc/.test(str);
/abc/.test('lit');
/abc/.test(`tpl`);
/abc/.test(obj.text);
/abc/.test(obj['text']);
/abc/.test(obj.f());
// Other arguments get parentheses.
/abc/.test(str + 'x');
/abc/.test(cond ? str : 'x');
/abc/.test(str as string);
/abc/.test(str!);
/abc/.test(obj?.text);
/abc/.test(tag`x`);
/abc/.test((str));
/abc/.test((str + 'x'));
/abc/?.test(str);
// The text is escaped for a single-quoted string.
/a'b/.test(str);
/a\\b/.test(str);
/a\tb\nc/.test(str);
/a\0b/.test(str);
/\v\f\r/.test(str);
/a\/b"c/.test(str);
/ñ😀/.test(str);
/😀/u.test(str);
// A RegExp that is not a literal.
new RegExp('abc').test(str);
const re = /abc/;
re.test(str);
// Comments and several lines.
/abc/ /* a */ .test( /* b */ str /* c */ );
/abc/
  .test(
    str,
  );
// Non-ASCII text on the same line.
const ñ = '😀'; /日本/.test(str); const 語 = arr.indexOf(1) === -1;
