// prefer-string-starts-ends-with with the default options.
declare const s: string;
declare const t: string;
declare const literal: 'abc' | 'def';
declare const maybe: string | undefined;
declare const items: string[];
declare const obj: { s: string };
declare const anything: any;

// Reported: single elements.
s[0] === 'a';
s[0] !== 'a';
s[0] == 'a';
s[s.length - 1] === 'a';
s.charAt(0) === 'a';
s.charAt(s.length - 1) === 'a';
literal[0] === 'a';
obj.s[obj.s.length - 1] === 'a';
s[0] === t;
(s)[0] === 'a';
maybe![0] === 'a';

// Reported: indexOf, lastIndexOf and match.
s.indexOf('bar') === 0;
s.indexOf(t) !== 0;
s.lastIndexOf('bar') === s.length - 3;
s.lastIndexOf(t) === s.length - t.length;
s.match(/^bar/) === null;
s.match(/bar$/) !== null;
s.match(/^bar/) == null;
s.match(/^a\/b/) === null;
s.match(/^😀/u) === null;

// Reported: slice and substring.
s.slice(0, 3) === 'bar';
s.slice(0, t.length) === t;
s.slice(-3) === 'bar';
s.slice(-t.length) === t;
s.slice(s.length - 3) === 'bar';
s.slice(s.length - t.length) === t;
s.slice(-3, s.length) === 'bar';
s.slice(-3, 0) === 'bar';
s.substring(0, 3) === 'bar';
s.substring(s.length - 3) === 'bar';
s['slice'](0, 3) === 'bar';
s.slice(0, 2) !== '😀';
/* 😀 */ s.slice(0, 3) === 'bar';

// Reported: RegExp#test, without a type check.
/^bar/.test(s);
/bar$/.test(s);
/^bar/.test(anything);
/^bar/.test(items);
/^a{1/.test(s);
/^bar/?.test(s);

// Reported: constants (resolved with the scope).
const PREFIX = 'ab';
const STARTS = /^ab/;
s.slice(0, PREFIX.length) === PREFIX;
s.indexOf(t) === (0 as const);
STARTS.test(s);
s.match(STARTS) === undefined;
s.match(/bar$/) === void 0;

// Not reported.
s[1] === 'a';
s[s.length - 2] === 'a';
s[0] + 'a';
s[0] < 'a';
items[0] === 'a';
s['0'] === 'a';
maybe?.[0] === 'a';
maybe?.charAt(0) === 'a';
anything[0] === 'a';
s.charAt(1) === 'a';
s.charAt() === 'a';
s.indexOf('bar') === 1;
s.indexOf('bar', 1) === 0;
s.lastIndexOf('bar') === s.length - 2;
s.lastIndexOf('bar') === t.length - 3;
s.match(/^bar/) === 0;
s.match(/^bar$/) === null;
s.match(/bar/) === null;
s.match(/^bar/i) === null;
s.match(/^bar/m) === null;
s.match(/^ba+r/) === null;
s.match(/^bar/, 1 as never) === null;
s.slice(0, 2) === 'bar';
s.slice(1, 3) === 'bar';
s.slice(-2) === 'bar';
s.slice(0, t.length) === s;
s.substr(0, 3) === 'bar';
items.slice(0, 3) === 'bar' as unknown;
/^bar$/.test(s);
/bar/.test(s);
/^bar/.test(s, 1);
/^ba|r/.test(s);
/^bar/i.test(s);
// A character or null through a Map, a Set and the functions of Object (static values).
s[0] === new Map([[1, 'a']]).get(1);
s.charAt(0) === [...new Set('a')][0];
s[s.length - 1] === Object.values('a')[0];
s.match(/^bar/) === new Map().get('missing');
s.match(/bar$/) != Object(null).missing;
s[0] === new Map([[1, 'ab']]).get(1);
