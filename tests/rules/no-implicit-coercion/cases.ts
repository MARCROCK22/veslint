declare let a: any;
declare const s: string;

// Reported.
const b1 = !!a;
const n1 = +a;
const n2 = - -a;
const n3 = a * 1;
const n4 = 1 * a;
const n5 = a - 0;
const s1 = '' + a;
const s2 = a + '';
const s3 = `` + a;
a += '';
const b2 = ~s.indexOf('x');
const b3 = ~s?.lastIndexOf('x');
const b4 = typeof+a;

// Not reported.
const k1 = Boolean(a);
const k2 = Number(a);
const k3 = +1;
const k4 = +Number(a);
const k5 = a * 2;
const k6 = '' + 'x';
const k7 = String(a) + '';
const k8 = a * 1 / 2;
const k9 = ~a;
const k10 = `${a}`;
