// unicorn/prefer-ternary: an `if`/`else` whose branches return, yield, await, throw or assign to
// the same reference becomes a ternary. With "only-single-line" (only-single-line/), only when the
// test and both branches are on one line each.
declare let a: boolean, b: number, c: number;
declare let o: { p: number };
declare function f(): number;

function g1() {
  if (a) {
    return b;
  } else {
    return c;
  }
}
function g2() {
  if (a) return; else return c;
}
function* g3() {
  if (a) {
    yield b;
  } else {
    yield c;
  }
}
function* g4() {
  if (a) {
    yield* [b];
  } else {
    yield* [c];
  }
}
async function g5() {
  if (a) {
    await f();
  } else {
    await b;
  }
}
function g6() {
  if (a) {
    throw new Error('b');
  } else {
    throw new TypeError('c');
  }
}
// The new variable takes a name no scope uses.
function g7(error: unknown, error_: unknown) {
  if (a) {
    throw error;
  } else {
    throw error_;
  }
}
// Without a block around the `if`, the fix adds one.
function g8() {
  for (;;)
    if (a) throw b;
    else throw c;
}
if (a) {
  b = 1;
} else {
  b = 2;
}
if (a) o.p += 1;
else o['p'] += 2;
if (a) {
  b = (c, 1);
} else {
  b = c as number;
}
// Multi-line branches: reported only without "only-single-line".
if (a) {
  b = f(
    1,
  );
} else {
  b = 2;
}
// A comment: reported without the fix.
if (a) {
  b = 1; // one
} else {
  b = 2;
}
// A `;` keeps the fixed statement from joining the one before it.
let y = 1
if ((a)) {
  [b] = [1];
} else {
  [b] = [2];
}

// Not reported.
if (a) {
  b = 1;
}
if (a) {
  b = 1;
} else if (c) {
  b = 2;
} else {
  b = 3;
}
if (a) {
  b = 1;
} else {
  c = 2;
}
if (a) {
  b = 1;
  c = 1;
} else {
  b = 2;
}
if (a ? b : c) {
  b = 1;
} else {
  b = 2;
}
function h1() {
  if (a) {
    return b ? 1 : 2;
  } else {
    return c;
  }
}
if (a) {
  b = 1;
} else {
  b -= 2;
}
