// prefer-regexp-exec: String#match without the global flag.
declare const text: string;
declare const literal: 'abc';
declare const maybe: string | undefined;
declare const re: RegExp;
declare const pattern: string;
declare const either: RegExp | string;
declare const unknownValue: unknown;
declare const anything: any;
declare const notString: { match(x: unknown): unknown };
declare function consume(value: unknown): void;

// Reported: a regular expression without `g`, a string the RegExp constructor accepts, or a
// RegExp built without `g`, on a string.
text.match(/thing/);
text.match(/thing/i);
literal.match(/b/);
text.match('thing');
text.match("[a-z]+");
text['match'](/x/);
text[`match`](/x/);
maybe!.match(/x/);
text.match(RegExp('x'));
text.match(new RegExp('x'));
text.match(new RegExp('x', 'i'));
text.match(RegExp(pattern));
text.match(new RegExp(pattern, 'm'));
text.match(new RegExp);
(text).match(/x/);
/* 😀 */ text.match(/x/);
`${text}`.match(/x/);
(text + 'suffix').match(/x/);

// Reported: constants without the global flag.
const SIMPLE = /x/;
const SIMPLE_TEXT = 'x';
text.match(SIMPLE);
text.match(SIMPLE_TEXT);

// Not reported: the global flag, or a string RegExp rejects.
text.match(/thing/g);
text.match(/thing/gi);
text.match(new RegExp('x', 'g'));
text.match(RegExp('x', 'gu'));
text.match('(');
text.match('?');
text.match('[z-a]');
const GLOBAL = /x/g;
text.match(GLOBAL);
const flags = 'gi';
text.match(new RegExp('x', flags));

// Not reported: the value may have the global flag, the argument type is neither RegExp nor
// string, or the object is not a string.
text.match(re);
text.match(pattern);
maybe?.match(/x/);
text.match(new RegExp(pattern, pattern));
text.match(either);
text.match(unknownValue as string | RegExp);
text.match(anything);
text.match(/a/, 1 as never);
notString.match(/x/);
anything.match(/x/);
text.matchAll(/x/g);
text.search(/x/);

// The member may also be the single argument of a call: reported only when it is static and
// the argument is a RegExp or a string.
consume(text.match);
consume(text?.match);

// A string literal with a surrogate that has no pair is a string all the same: the regular
// expression of the fix has that surrogate, which is U+FFFD once written in UTF-8.
text.match('\ud800');
text.match('a\ud800b');
text.match('\udc00\ud800');
text.match('😀');
text.match('\u{d800}');
text.match(`\udfff`);
// A static argument through a Map, a Set and Object.values.
text.match(new Map([[1, /x/]]).get(1)!);
text.match([...new Set(['abc'])][0]);
text.match(Object.values({ a: /x/g })[0]);
text.match(Object.values(['x'])[0]);
