declare let a: any;
declare let b: any;

// Reported without allowInParentheses.
const z = (a, b);
if ((a, b)) {}

// Not reported.
for (a = 0, b = 0; ; a++, b++) {}
