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

// A `;` or parentheses around the fix when the statement would continue the line before or start
// with `{`, `function` or `class` (10.15.0).
declare function go(): boolean;
declare let x2: any;
go()
0 === [a, b2].indexOf(x2) && go()
go()
0 === (a || b2) && go()
x2++
0 === +x2 && go()
x2--
0 === /a/.lastIndex && go()
go()
0 === `${a}` && go()
go()
x2 === -1 && go()
1 < {}.x && go();
null > function* () {};
0 === async function () {}.length;
0 === class {}.name;
const f2 = () => 1 < {}.x
go()
1 < {}.x && go()
go();
0 === [a].indexOf(x2) && go();
go()
0 === x2.y && go()
if (1 < {}.x) {}
(1 < {}.x) && go();
const f3 = () => (1 < {}.x)
export default 1 < function () {}.x;
