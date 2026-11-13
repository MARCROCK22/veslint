declare let a: any;
declare let b: any;
declare const o: any;

// Reported with enforceForIfStatements.
if (a) a = b;
if (!a) a = b;
if (a == null) a = b;
if (a === null || a === undefined) a = b;
if (o.p) {
  o.p = b;
}
if (Boolean(a)) a = b;
if (!!a) a = b;

// Not reported.
if (a) b = a;
if (a) a = b; else b = a;
if (a) {
  a = b;
  b = a;
}
