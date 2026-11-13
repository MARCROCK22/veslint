// unicorn/no-negated-condition: an `if` with `else`, or a conditional, whose test is negated
// (`!a`, `a != b`, `a !== b`) swaps its branches.
declare let a: boolean, b: number, c: number;
declare function foo(): void;
declare function bar(): void;
declare function f(): unknown;

// Reported, with the fix.
if (!a) {
  foo();
} else {
  bar();
}
if (b != c) {
  foo();
} else {
  bar();
}
if (b !== c) foo();
else bar();
if (!(a)) foo(); else { bar(); }
const x1 = !a ? b : c;
const x2 = b !== c ? b : c;
const x3 = (!a) ? (b) : (c);
// The same branches: only the test changes.
if (!a) {
  foo();
} else {
  foo();
}

// TypeScript: assertions in the test.
if (!(a as boolean)) {
  foo();
} else {
  bar();
}
const x4 = <number>b != c ? 1 : 2;

// A keyword right before the conditional takes a space.
function g1() {
  return!a ? b : c;
}
function* g2() {
  yield!a?b:c;
}
// `return` with the test on two lines takes parentheses.
function g3() {
  return !
    a ? b : c;
}
function g4() {
  throw !
    a ? b : c;
}
// A `;` keeps the conditional from joining the statement before it.
let y = 1
!a ? foo() : bar();
f()
!a ? foo() : bar()

// Not reported.
if (!a) {
  foo();
}
if (!a) {
  foo();
} else if (b) {
  bar();
}
if (a) {
  foo();
} else {
  bar();
}
if (b == c) foo(); else bar();
const z1 = a ? b : c;
const z2 = !a && b ? b : c;
