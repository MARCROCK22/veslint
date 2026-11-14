// unicorn/consistent-date-clone: `new Date(date)` clones a date, without `.getTime()`.
declare const date: Date;
declare const box: { date: Date };

const d1 = new Date(date.getTime());
const d2 = new Date(box.date.getTime());
const d3 = new Date((date).getTime());
const d4 = new Date(((date).getTime)());
const d5 = new Date((date as Date).getTime());
const d6 = new Date(date!.getTime());

// Not reported.
const z1 = new Date(date);
const z2 = new Date(date.getTime(), 1);
const z3 = new Date(date?.getTime());
const z4 = new Date(date.getTime?.());
const z5 = new Date(date['getTime']());
const z6 = new Date(date.valueOf());
const z7 = Date(date.getTime());

// 79.0.0: no fix when a comment would be lost; comments inside the kept object are fine.
declare const date2: Date;
new Date(new Date(date2.getTime()).getTime());
new Date(date2 /* comment */.getTime());
new Date(date2.getTime /* comment */());
new Date(date2.getTime() /* comment */);
new Date(date2 // comment
	.getTime());
new Date((date2 as Date).getTime());
new Date((date2 /* comment */).getTime());
