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
if (z3 < 0) {}
const z4 = list.includes(1);
