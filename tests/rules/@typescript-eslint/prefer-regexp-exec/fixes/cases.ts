// prefer-regexp-exec: the fix swaps the object and the argument around `.exec()`.
// Non-ASCII text before the ranges: ñ 😀 日本語.
declare const text: string;
declare const pattern: string;
declare const cond: boolean;
declare const obj: { s: string; re: RegExp; f(): string };
const localRe = /abc/;
const localPattern = 'abc';

// A string literal: the source of the RegExp it gives.
text.match('abc');
text.match('a/b');
text.match('');
text.match('\n');
text.match("ñ😀");
text.match('[/]');
// A RegExp.
text.match(/abc/);
text.match(localRe);
text.match(new RegExp('a'));
text.match(RegExp('a', 'i'));
text.match(RegExp(pattern));
text.match(true ? /a/ : /b/);
text.match((/a/));
text.match(localRe as RegExp);
// Another string.
text.match(localPattern);
text.match(`abc`);
text.match('a' + 'b');
text.match(localPattern!);
// The object.
obj.s.match(/a/);
obj.f().match(/a/);
(text).match(/a/);
(text + 'x').match(/a/);
`tpl`.match(/a/);
'lit'.match(/a/);
text['match'](/a/);
(cond ? text : 'x').match(/a/);
(text as string).match(/a/);
text!.match(/a/);
obj?.s.match(/a/);
(obj?.s).match(/a/);
// A parent that binds tighter: parentheses, unless the call has them.
text.match(/a/)!.length;
text.match(/a/)?.length;
text.match(/a/)[0];
!text.match(/a/);
!obj?.s.match(/a/);
text.match(/a/) || null;
(text.match(/a/)) || null;
text.match(/a/) ? 1 : 2;
typeof text.match(/a/);
async function awaited() {
  await text.match(/a/);
}
const arrow = () => text.match(/a/);
// After a statement without a semicolon, code that starts with `(` gets one.
const before = 1
text.match(true ? /a/ : /b/)
const after = 2;
text.match(true ? /a/ : /b/);
function inBlock() {
  const inner = 1
  text.match(true ? /a/ : /b/)
  text.match(/a/) || null
  text.match(/a/)?.[0]
  text.match(/a/)
}
namespace InNamespace {
  const inner = 1
  text.match(true ? /a/ : /b/)
}
if (cond) text.match(true ? /a/ : /b/)
// Comments and several lines.
text /* a */ .match( /* b */ /abc/ /* c */ );
text
  .match(
    /abc/,
  );
// Non-ASCII text on the same line.
const ñ = '😀'; text.match(/ñ/); const 日本 = '語'; text.match('語');
