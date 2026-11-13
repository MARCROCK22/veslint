declare let a: number;
declare let b: number;
declare const o: any;

// Reported with "never".
a += b;
a -= b + 1;
a *= b + 1;
o.p += 1;
a+=+b;
a **= 2;
o.p.q -= 1;

// Not reported.
a = a + b;
a ||= 1 as any;
