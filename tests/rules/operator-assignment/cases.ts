declare let a: number;
declare let b: number;
declare const o: any;

// Reported with "always".
a = a + b;
a = a - b;
a = a * b;
a = b * a;
a = a ** 2;
o.p = o.p + 1;
o['q'] = o['q'] * 2;
this.x = this.x | 1;
a = a /* c */ + b;
o.p.q = o.p.q + 1;

// Not reported.
a = b + a;
a = a + b + 1 - 1 + a;
a += b;
a = a && b;
