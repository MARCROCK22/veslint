// unicorn/no-negation-in-equality-check: `!a === b` suggests `a !== b`.
declare let a: unknown, b: unknown;
declare function f(): unknown;

// Reported, with the suggestion.
const x1 = !a === b;
const x2 = !a !== b;
const x3 = !a == b;
const x4 = !a != b;
const x5 = !(a as boolean) === b;
const x6 = !f() === (b);
const x7 = ! /* comment */ a === b;
// The negation in parentheses too.
const x8 = (!a) === b ? 1 : 2;
// A keyword right before takes a space; `return` with the operand on another line takes
// parentheses.
function g1() {
  return!a === b;
}
function g2() {
  return !
    a === b;
}
function g3() {
  throw !
    a === b
}
// A `;` keeps the expression from joining the statement before it.
let y = 1
!(a) === b;
f()
![a] === b

// Not reported.
const z1 = !!a === b;
const z2 = a === !b;
const z3 = !a > (b as number);
