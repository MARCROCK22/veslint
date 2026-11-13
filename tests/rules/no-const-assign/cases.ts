declare let x: any;

// Reported (TypeScript reports them too).
const a = 0;
// @ts-expect-error
a = 1;
const b = 0;
// @ts-expect-error
b += 1;
const c = 0;
// @ts-expect-error
c++;
const { d } = x;
// @ts-expect-error
d = 1;
const e = 0;
// @ts-expect-error
for (e of [1]) {}

// Not reported.
let g = 0;
g = 1;
const h = 0;
const i = h + 1;
for (const j of [1]) {}
