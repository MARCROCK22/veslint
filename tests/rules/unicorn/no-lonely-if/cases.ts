// unicorn/no-lonely-if: an `if` that is the only statement of an `if` without `else` joins its
// test to the outer one with `&&`.
declare let a: boolean, b: boolean, c: boolean, d: number;
declare function foo(): void;
declare function bar(): void;

// Reported, with the fix.
if (a) {
  if (b) {
  }
}
if (a) if (b) {
  foo();
}
if (a) {
  if (b) foo();
}
if (a) if (b) foo();
if (a) if (b);

// Tests with a lower precedence than `&&` keep their parentheses.
if (a || b) {
  if (c ?? a) {
    foo();
  }
}
if (a ? b : c) {
  if ((d = 1)) {
    foo();
  }
}
if (((a))) {
  if (b, c) {
    foo();
  }
}

// TypeScript: assertions, `satisfies` and non-null assertions in the tests.
if (a as boolean) {
  if (<boolean>b) {
    foo();
  }
}
if (a satisfies boolean) {
  if (c!) {
    foo();
  }
}

// Comments inside the outer block.
if (a) {
  // leading comment
  if (b) {
    foo(); // trailing comment
  }
  /* end */
}

// Without a `;`, a `;` keeps the next statement from joining the fixed one.
if (a) {
  if (b) foo()
}
[1, 2].forEach(foo);
if (a) {
  if (b) foo()
}
bar();

// Nested three times: each inner `if` is reported.
if (a) {
  if (b) {
    if (c) {
      foo();
    }
  }
}

// Not reported.
if (a) {
  if (b) {
  }
} else {
}
if (a) {
  if (b) {
  }
  foo();
} else {
}
if (a) {
} else {
  if (b) {
  }
}
if (a) {
  b ? foo() : bar();
}
if (a) {
  if (b) {
  } else {
  }
}
function f(): void {
  if (a) {
    if (b) {
      foo();
    }
    return;
  }
}
