// prefer-string-starts-ends-with: the fixes. Non-ASCII text before the ranges: ñ 😀 日本語.
declare const s: string;
declare const t: string;
declare const obj: { s: string };
const CH = 'x';
const slice = 'slice';

// One element compared with one character.
s[0] === 'a';
s[0] !== 'a';
s[0] == 'a';
s[0] != "a";
s.charAt(0) === 'a';
s[s.length - 1] === 'a';
s.charAt(s.length - 1) !== 'a';
s[0] === CH;
s[0] === 'ñ';
// Not one character: reported without a fix.
s[0] === 'ab';
s[0] === '';
s[0] === '😀';
s[0] === t;
// Parentheses, comments, several lines and optional chains.
(s)[0] === 'a';
(s[0]) === 'a';
s[0] === ('a');
s /* a */ [0] /* b */ === /* c */ 'a' /* d */;
s
  .charAt(0)
  === 'a';
obj.s[0] === 'a';
obj?.s[0] === 'a';
obj.s?.[0] === 'a';
obj.s?.charAt(0) !== 'a';

// indexOf and lastIndexOf: the argument stays.
s.indexOf('abc') === 0;
s.indexOf('abc') !== 0;
s.indexOf(t) == 0;
(s).indexOf(t) === 0;
s.indexOf(t) === (0);
obj.s?.indexOf(t) === 0;
s.lastIndexOf('bar') === s.length - 3;
s.lastIndexOf(t) !== s.length - t.length;
s /* a */ . /* b */ lastIndexOf(t) === s.length - t.length;

// match: the text of the regular expression becomes the argument.
s.match(/^abc/) === null;
s.match(/abc$/) !== null;
s.match(/^abc/) == null;
s.match(/abc$/) != undefined;
s.match((/^a"b\\c/)) === null;
s.match(/^\n\t\x01\//) === null;
s.match(/^ñ😀/) === null;
s.match(/^😀/u) === null;
obj.s?.match(/^a/) === null;

// slice and substring.
s.slice(0, 3) === 'bar';
s.slice(0, 3) !== 'bar';
s.slice(0, 3) == 'bar';
s.slice(0, t.length) === t;
s.slice(-3) === 'bar';
s.slice(-t.length) === t;
s.slice(s.length - t.length) === t;
s.substring(s.length - 3) === 'bar';
s.slice(s.length - 3, s.length) === 'bar';
s.slice(-3, s.length) === 'bar';
s.substring(0, 3) === 'bar';
s['slice'](0, 3) === 'bar';
s[slice](-3) === 'bar';
obj.s?.slice(0, 3) === 'bar';
s.slice(0, 3) === ('bar');
// Reported without a fix: `==` against something that is not a string literal, a length that
// does not match, a negative index for substring or for a computed `slice`.
s.slice(0, t.length) == t;
s.slice(0, 3) === t;
s.substring(-3) === 'bar';
s['slice'](-3) === 'bar';
s.slice(-3, 0) === 'bar';

// test: the argument becomes the object.
/^abc/.test(s);
/abc$/.test(s);
/^abc/.test(s + t);
/^abc/.test((s));
/^a"b/.test(obj.s);
/^abc/?.test(s);
/^abc/.test(obj?.s);
/^abc/ /* a */ .test( /* b */ s /* c */ );

// Non-ASCII text on the same line.
const ñ = '😀'; s[0] === 'ñ'; /^日本/.test(s); s.match(/語$/) === null; s.slice(0, 2) === '日本';
