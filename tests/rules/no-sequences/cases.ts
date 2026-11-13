declare let a: any;
declare let b: any;
declare function f(): void;

// Reported.
a = 1, b = 2;
f(), f();
const x = (a, b), y = 1;
if (a, b) {}
while (a, b) {}
switch (a, b) {}
const g = () => (a, b);
const h = a ? (b, a) : b;

// Not reported.
for (a = 0, b = 0; a < 1; a++, b++) {}
const z = (a, b);
if ((a, b)) {}
const k = () => ((a, b));
