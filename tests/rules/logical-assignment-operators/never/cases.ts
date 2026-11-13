declare let a: any;
declare let b: any;
declare const o: any;

// Reported with "never".
a ||= b;
a &&= b;
a ??= b;
o.p ||= b;
a ||= b || 1;
a ??= b || 1;
a &&= b ? 1 : 2;

// Not reported.
a = a || b;
a += 1;
