// The code path of a `switch` is the one of the function, method or static block around it,
// which starts afresh there: each kind of them, nested ones and code that never runs around them.
declare function work(n: number): void;
declare const n: number;
async function asyncFalls(): Promise<void> {
  await Promise.resolve();
  switch (n) {
    case 1:
      work(1);
    case 2:
      work(2);
  }
}
function* generatorFalls(): Generator<number> {
  switch (n) {
    case 1:
      yield 1;
    case 2:
      yield 2;
  }
}
const arrowFalls = async (): Promise<void> => {
  switch (n) {
    case 1:
      work(1);
    default:
      work(2);
  }
};
const expressionFalls = function (): void {
  switch (n) {
    case 1:
      work(1);
    // falls through
    case 2:
      work(2);
    case 3:
      work(3);
  }
};
class Members {
  value = (): void => {
    switch (n) {
      case 1:
        work(1);
      case 2:
        work(2);
    }
  };
  static {
    switch (n) {
      case 1:
        work(1);
      case 2:
        work(2);
    }
  }
  constructor() {
    switch (n) {
      case 1:
        work(1);
      case 2:
        work(2);
    }
  }
  get size(): number {
    switch (n) {
      case 1:
        return 1;
      case 2:
        work(2);
      case 3:
        return 3;
    }
    return 0;
  }
  method(): void {
    switch (n) {
      case 1:
        throw new Error('one');
      case 2:
        work(2);
      default:
        work(3);
    }
  }
}
const object = {
  method(): void {
    switch (n) {
      case 1:
        work(1);
      case 2:
        work(2);
    }
  },
};
// A function after a `return` or a `throw` has a code path of its own, which runs.
function afterReturn(): void {
  return;
  function inner(): void {
    switch (n) {
      case 1:
        work(1);
      case 2:
        work(2);
    }
  }
}
function afterThrow(): void {
  throw new Error('never');
  const inner = (): void => {
    switch (n) {
      case 1:
        work(1);
      case 2:
        work(2);
    }
  };
}
// A switch in a function in a case of another switch, and in a default value.
function nested(m: number): void {
  switch (m) {
    case 1:
      [1].forEach((x) => {
        switch (x) {
          case 1:
            work(1);
          case 2:
            work(2);
        }
      });
    case 2:
      work(2);
  }
}
function defaults(
  f = (): void => {
    switch (n) {
      case 1:
        work(1);
      case 2:
        work(2);
    }
  },
): void {
  f();
}
// Unreachable code inside the function: the cases after a `return` never fall through.
function unreachable(): void {
  label: {
    break label;
  }
  if (n > 0) {
    return;
  } else {
    throw new Error('no');
  }
  switch (n) {
    case 1:
      work(1);
    case 2:
      work(2);
  }
}
export { arrowFalls, expressionFalls, Members, object, afterReturn, afterThrow, nested, defaults, unreachable };
