declare const obj: any;
let n = 0;

// Reported with disallowArithmeticOperators.
obj?.a + 1;
1 - obj?.a;
obj?.a * obj?.b;
obj?.a / 2;
obj?.a % 2;
obj?.a ** 2;
+obj?.a;
-obj?.a;
n += obj?.a;
n -= obj?.a;
n *= obj?.a;
n /= obj?.a;
n %= obj?.a;
n **= obj?.a;
(obj?.a || obj?.b) + 1;
(obj?.a).b;

// Not reported.
(obj?.a ?? 0) + 1;
obj?.a < 1;
~obj?.a;
n |= obj?.a;
n = obj?.a;
`${obj?.a}` + 1;
