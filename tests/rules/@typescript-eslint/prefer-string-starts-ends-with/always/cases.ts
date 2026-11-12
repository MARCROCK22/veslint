// prefer-string-starts-ends-with with allowSingleElementEquality: 'always'.
declare const s: string;

// Not reported: single element equality is allowed.
s[0] === 'a';
s.charAt(0) === 'a';
s[s.length - 1] === 'a';
s.charAt(s.length - 1) !== 'a';

// Reported: the other forms.
s.indexOf('bar') === 0;
s.slice(0, 3) === 'bar';
s.match(/bar$/) === null;
