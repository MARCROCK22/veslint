declare let a: number | null, b: number, c: { d?: number } | undefined, o: object, F: Function;
declare let arr: number[];
// Reported, with the suggestions of a TSNonNullExpression on the left.
a! = b;
a! == b;
a! === b;
a! in o;
a! instanceof F;
a!! == b;
c!.d! = b;
arr[0]! === b;
a! /* comment */ == b;
a!
  == b;
a!/* c */ == b;
// Reported with the wrapping suggestion only: the left is not a TSNonNullExpression.
b + a! == 3;
b + a! === 3;
b + a! in o;
b * a! instanceof F;
c?.d! == b;
(c?.d)! === b;
// Not reported.
(a!) = b;
(a!) == b;
(a!) in o;
a != b;
a !== b;
a! != b;
a! += b;
a! < b;
a == b!;
a! + b;
for (const k in o) {}
((a!)) === b;
