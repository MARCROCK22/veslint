// unicorn/prefer-ternary with "only-single-line" and checkVaryingBase: varying callees, only on
// single lines; checkComputedMemberAccess stays off.
declare let test: boolean, value: number;
declare let object: { a(value: number): void; b(value: number): void };
declare function f(): void;
declare function g(): void;
declare function h(value: number): void;

if (test) { f(); } else { g(); }
if (test) { h(
  value,
); } else { h(2); }
if (test) { object.a(value); } else { object.b(value); }
