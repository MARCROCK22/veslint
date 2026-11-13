declare const a: any;
declare const b: any;

// Reported.
if (!!a) {}
if (Boolean(a)) {}
while (!!a) {}
do {} while (Boolean(a));
for (; !!a; ) {}
const t1 = !!a ? 1 : 2;
const t2 = !!!a;
const t3 = !Boolean(a);
const t4 = Boolean(!!a);
const t5 = new Boolean(!!a);
if (Boolean()) {}
const t6 = !Boolean();
if (!!(a, b)) {}
if (Boolean(a ? 1 : 2)) {}
const t7 = !(!!a);
if (!/* c */!a) {}
const t8 = typeof!!a;

// Not reported.
const k1 = !!a;
const k2 = Boolean(a);
if (a && !!b) {}
if (!!a || b) {}
function shadow(Boolean: (x: unknown) => boolean) {
  if (Boolean(a)) {}
}
