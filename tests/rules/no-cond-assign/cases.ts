declare let a: any;
declare let b: any;
declare function next(): any;

// Reported: an assignment as the test, without the extra parentheses.
if (a = b) {}
while (a = next()) {}
do {} while (a = next());
for (; a = next(); ) {}
const t1 = (a = b) ? 1 : 2;
if (a += 1) {}
if (a ||= b) {}
if ((a = b) && a) {}
const t2 = a ? (b = 1) : 2;
if (/* c */ a = b) {}

// Not reported: parenthesised twice (once in a `for`), or not the test itself.
if ((a = b)) {}
while ((a = next())) {}
do {} while ((a = next()));
for (; (a = next()); ) {}
const t3 = ((a = b)) ? 1 : 2;
if (a === b) {}
if ((a = b), a) {}
for (a = 0; a < 1; a = a + 1) {}
const t4 = (a = b ? 1 : 2);
if (f(a = b)) {}
function f(x: any): boolean {
  return x;
}
