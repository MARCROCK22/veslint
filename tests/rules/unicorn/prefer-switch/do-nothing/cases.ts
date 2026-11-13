// unicorn/prefer-switch: three or more `if`/`else if` that compare the same reference with `===`
// become a `switch` (minimumCases: 2 in two-cases/; the empty default case of the options in
// do-nothing/ and no-default-case/).
declare let a: number, b: number;
declare let o: { p: number };
declare function f(): number;
declare function g(n: number): void;

if (a === 1) {
  g(1);
} else if (a === 2) {
  g(2);
} else if (a === 3 || a === 4) {
  g(3);
} else {
  g(0);
}
if (o.p === 1) g(1);
else if (2 === o['p']) g(2);
else if (o.p === 3) g(3);
function h1() {
  if (a === 1) {
    return 1;
  } else if (a === 2) {
    throw new Error('2');
  } else if (a === 3) {
    if (b) {
      return 3;
    } else {
      return 4;
    }
  }
  return 0;
}
// Two cases: only with minimumCases: 2.
if (a === 1) {
  g(1);
} else if (a === 2) {
  g(2);
}
// A side effect in the discriminant: reported without the fix.
if (f() === 1) {
  g(1);
} else if (f() === 2) {
  g(2);
} else if (f() === 3) {
  g(3);
}
// A `break` that would break out of the `switch`: reported without the fix.
for (;;) {
  if (a === 1) {
    break;
  } else if (a === 2) {
    g(2);
  } else if (a === 3) {
    g(3);
  }
}
// A `break` of a loop inside the branch does not count.
if (a === 1) {
  for (;;) {
    break;
  }
} else if (a === 2) {
  g(2);
} else if (a === 3) {
  g(3);
}
// TypeScript: assertions on the reference.
if ((a as number) === 1) {
  g(1);
} else if (a! === 2) {
  g(2);
} else if (<number>a === 3) {
  g(3);
}

// Not reported.
if (a === 1) {
  g(1);
} else if (b === 2) {
  g(2);
} else if (a === 3) {
  g(3);
}
if (a == 1) {
  g(1);
} else if (a == 2) {
  g(2);
} else if (a == 3) {
  g(3);
}
if (a === 1 && b) {
  g(1);
} else if (a === 2) {
  g(2);
} else if (a === 3) {
  g(3);
}
