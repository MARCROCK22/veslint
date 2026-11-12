// no-dupe-else-if: a condition of an if-else-if chain that an earlier one covers.
declare const a: boolean, b: boolean, c: boolean, d: boolean;
declare const n: number;
declare function f(value: number): boolean;

// The same condition again, as written or with other parentheses and comments.
if (a) {} else if (a) {}
if (n === 1) {} else if (n === 2) {} else if (n === 1) {}
if (f(1)) {} else if ((f(1))) {}
if (a /* first */) {} else if (/* again */ a) {}
if (n > 0) {} else if (n /* comment */ > 0) {}

// Covered by an earlier `||`, or every part of an `&&` covered.
if (a || b) {} else if (a) {}
if (a) {} else if (b) {} else if (a || b) {}
if (a && b) {} else if (a && b && c) {}
if (a) {} else if (a && b) {}
if (a || b) {} else if (b || a) {}
if ((a && b) || c) {} else if (c || (b && a)) {}

// Not covered: other operands, other operators, another chain.
if (a) {} else if (b) {}
if (a && b) {} else if (a) {}
if (a ?? b) {} else if (b ?? a) {}
if (n === 1) {} else if (n == 1) {}
if (a) {} else { if (a) {} }
if (a) {} if (a) {}

// TypeScript: the same types and assertions are the same tokens.
declare const v: unknown;
if (typeof v === 'string') {} else if (typeof v === 'string') {}
if ((v as string).length) {} else if ((v as string).length) {}
if (v!) {} else if (v) {}
