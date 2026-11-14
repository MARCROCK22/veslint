// unicorn/consistent-existence-index-check: `=== -1` and `!== -1` for the index of an element.
declare const list: number[];

const index = list.indexOf(1);
if (index < 0) {}
if (index >= 0) {}
if (index > -1) {}
const last = list.lastIndexOf(1);
const found = last >= 0 ? 'yes' : 'no';
const position = list.findIndex(x => x > 1);
if (position < 0 || position >= 0) {}

// Not reported.
const z1 = list.indexOf(1);
if (z1 === -1) {}
if (z1 !== -1) {}
let z2 = list.indexOf(1);
if (z2 < 0) {}
const z3 = list.indexOf(1);
if (z3 < 1) {}
// 79.0.0: a comparison without a replacement no longer stops the checks of the variable.
if (z3 < 0) {}
const z4 = list.includes(1);

// 79.0.0: parentheses where the equality binds more loosely than the comparison it replaces.
declare let expected: boolean;
declare function foo(): void;
declare const ready: boolean;
declare const mask: number;
const pi = list.indexOf(2);
expected === pi < 0;
expected !== pi >= 0;
expected == pi > -1;
pi < 0 < expected;
pi >= 0 === expected;
expected === (pi < 0);
expected === ((pi < 0));
expected === pi /* before */ < /* after */ 0;
pi < 0 && expected;
pi < 0 | mask;
foo()
pi < 0 < 1
foo() // keep
pi < 0 < 1
if (ready)
pi < 0 < 1
foo()
pi < 0 as boolean
pi < 0 satisfies boolean;
