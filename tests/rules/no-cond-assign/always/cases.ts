declare let a: any;
declare let b: any;
declare function next(): any;
declare function f(x: unknown): boolean;

// Reported with "always": any assignment inside a test.
if ((a = b)) {}
while ((a = next())) {}
do {} while ((a = next()));
for (; (a = next()); ) {}
const t1 = ((a = b)) ? 1 : 2;
if ((a = b) && a) {}
if (f(a = b)) {}
if (f(() => (a = b))) {}
if (f(function () { a = b; return a; })) {}
if (f(class { x = (a = b); })) {}
if (f({ m() { a = b; }, [a = b]() {} })) {}
if (f(class { static { a = b; } })) {}
if (a) { a = b; }
const t2 = a ? (b = 1) : (b = 2);
while (a ??= b) {}
const t3 = (a = 1) ? ((b = 2) ? 1 : 2) : 3;

// Not reported.
a = b;
for (a = 0; a < 1; a = a + 1) {}
const t4 = (a = b ? 1 : 2);
