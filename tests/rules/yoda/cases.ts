declare let a: any;

// Reported with "never".
if ('red' === a) {}
if (true == a) {}
if (5 > a) {}
if (-1 < a) {}
if (`x` !== a) {}
if (null != a) {}
if (0 <= a.length) {}
if (1 < a&&a < 2) {}
const b = 1<a;
if ((1) === (a)) {}

// Not reported.
if (a === 'red') {}
if (1 === 2) {}
if (a < b2) {}
if (`${a}` === a) {}
declare const b2: number;
