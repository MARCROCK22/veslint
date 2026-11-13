declare let a: any;
declare let b: any;
declare const o: any;

// Reported with "always".
a = a || b;
a = a && b;
a = a ?? b;
o.p = o.p || b;
o['q'] = o['q'] ?? b;
a = a || b || 1;
a || (a = b);
a && (a = b);
o.p ?? (o.p = b);
const c = a || (a = b);
a = (a || b);

// Not reported.
a = b || a;
a = a + b;
a ||= b;
b || (a = b);
