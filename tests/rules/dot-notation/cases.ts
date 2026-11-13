declare const a: any;

// Reported.
const b = a['b'];
const c = a["c"];
const d = a[`d`];
const e = a['true'];
const f = a[true as any];
const g = a[null as any];
const h = a?.['h'];
const i = 1['toString'];
const j = a['class'];

// Not reported.
const k = a['k-l'];
const l = a[b];
const m = a['1'];
const n = a.n;
