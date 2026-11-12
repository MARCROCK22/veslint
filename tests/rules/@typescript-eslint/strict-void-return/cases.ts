// strict-void-return: functions that return a value where a void function is expected.
declare function run(cb: () => void): void;
declare function runWith(value: number, cb: (x: number) => void): void;
declare function maybe(cb?: () => void): void;
declare function either(cb: (() => void) | string): void;
declare function many(...cbs: (() => void)[]): void;
declare function generic<T>(cb: () => T): T;
declare function returnsNumber(cb: () => number): void;
declare function overloaded(cb: () => void): void;
declare function overloaded(cb: () => number, extra: number): void;
declare function anyOverload(name: 'a', cb: () => void): void;
declare function anyOverload(name: string, cb: () => any): void;
declare function allVoid(name: 'a', cb: () => void): void;
declare function allVoid(name: 'b', cb: (x: number) => void): void;
declare const numberFn: () => number;
declare const voidFn: () => void;
declare const undefinedFn: () => undefined;
declare const neverFn: () => never;
declare const anyFn: () => any;
declare const unknownFn: () => unknown;
declare const promiseFn: () => Promise<void>;
declare const unionFn: (() => number) | (() => void);
declare const anyValue: any;
declare const flag: boolean;

run(() => 1);
run(() => (2));
run(() => {
  return 3;
});
run(() => {});
run(() => undefined);
run(() => void 0);
run(() => {
  return;
});
run(() => {
  throw new Error('x');
});
run(async () => {});
run(async () => 1);
run(function () {
  return 'text';
});
run(function* () {});
run(async function () {});
run(numberFn);
run(voidFn);
run(undefinedFn);
run(neverFn);
run(anyFn);
run(unknownFn);
run(promiseFn);
run(unionFn);
run(() => anyValue);
run(() => {
  return anyValue;
});
run((): number => {
  return 1;
});
run((): void => {
  return anyValue;
});
run(function (): string | undefined {
  return undefined;
});
run((): asserts flag => {});
run(() => {
  if (flag) {
    return 1;
  } else {
    return 'a';
  }
  for (const x of [1]) {
    return x;
  }
  while (flag) {
    return flag;
  }
  do {
    return null;
  } while (flag);
  switch (anyValue) {
    case 1:
      return 1;
    default: {
      return 2;
    }
  }
  try {
    return 3;
  } catch {
    return 4;
  } finally {
    return 5;
  }
  label: {
    return 6;
  }
  const inner = () => {
    return 7;
  };
  function nested() {
    return 8;
  }
  return undefined;
  return void 0;
  return flag ? 1 : undefined;
});
runWith(1, x => x);
runWith(1, x => {
  return x + 1;
});
maybe(() => 1);
either(() => 1);
either('text');
many(() => 1, () => {}, async () => {});
generic(() => 1);
returnsNumber(() => 1);
overloaded(() => 1);
overloaded(() => 1, 2);
anyOverload('a', () => 1);
anyOverload('b', () => 1);
allVoid('a', () => 1);
allVoid('b', x => x);
run(...[() => 1]);
[1, 2].forEach(x => x * 2);
[1, 2].forEach(x => {
  return x;
});
[1, 2].map(x => x * 2);
new Promise<void>(resolve => resolve());
new Promise<void>((resolve, reject) => 1);
setTimeout(() => 1, 10);
document.addEventListener('click', () => 1);
document.addEventListener('click', async () => {});
Promise.resolve().then(() => 1);

// Declarations and assignments.
const typed: () => void = () => 1;
const typedBlock: () => void = () => {
  return 1;
};
const typedAsync: () => void = async () => {};
const typedReference: () => void = numberFn;
const untyped = () => 1;
let later: () => void;
later = () => 1;
later = numberFn;
let optional: (() => void) | undefined;
optional = () => 1;
optional ??= () => 2;
let count = 0;
count += 1;
const list: (() => void)[] = [() => 1, () => {}, numberFn, async () => {}, ...[() => 2]];
const tuple: [() => void, () => number] = [() => 1, () => 2];
const sparse: (() => void)[] = [, () => 1];

// Objects.
interface Handlers {
  onClick: () => void;
  onLoad(): void;
  onMaybe?: () => void;
  onNumber: () => number;
  readonly value: () => void;
}
const handlers: Handlers = {
  onClick: () => 1,
  onLoad() {
    return 1;
  },
  onMaybe: async () => {},
  onNumber: () => 1,
  get value() {
    return () => 1;
  },
};
const shorthandValue = () => 1;
const onClick = () => 1;
const shorthand: { onClick: () => void; other?: () => void } = { onClick };
const methods: { a(): void; b(): void; ['c'](): void; d: () => void; 1(): void; 'quoted'(): void } = {
  a() {
    return 1;
  },
  async b() {},
  ['c']() {
    return 1;
  },
  *d() {},
  1() {
    return 1;
  },
  'quoted'() {
    return 'q';
  },
};
const spread: Handlers = { ...handlers, onClick: () => 2 };
const noContext = {
  method() {
    return 1;
  },
};
const unknownMethod: { a(): void } = {
  a() {},
  // @ts-expect-error not in the type
  b() {
    return 1;
  },
};

// Returns.
function factory(): () => void {
  return () => 1;
}
function factoryReference(): () => void {
  return numberFn;
}
const arrowFactory = (): (() => void) => () => 1;
function nestedFactory(): () => () => void {
  return () => () => 1;
}

// Classes.
interface Listener {
  handle(): void;
  callback: () => void;
  other(): number;
}
class Base {
  method(): void {}
  property: () => void = () => {};
  static shared(): number {
    return 1;
  }
  untouched(): number {
    return 1;
  }
}
class Derived extends Base {
  method() {
    return 1;
  }
  property = () => 1;
  untouched() {
    return 2;
  }
  own() {
    return 3;
  }
}
class Implemented implements Listener {
  handle() {
    return 1;
  }
  callback = () => 1;
  other() {
    return 1;
  }
  static handle() {
    return 'static';
  }
  constructor() {}
  get accessor() {
    return 1;
  }
}
class Both extends Base implements Listener {
  async handle() {}
  callback = async () => {};
  other() {
    return 1;
  }
  override method(): number {
    return 1;
  }
  typedProperty: () => void = () => 1;
  declare declared: () => void;
  ['handle']() {
    return 2;
  }
}
abstract class Shape {
  abstract draw(): void;
  measure(): void {}
}
class Circle extends Shape {
  draw() {
    return 1;
  }
  measure = () => 1;
}
const Anonymous = class extends Base {
  method() {
    return 'expression';
  }
};
class Generic<T> {
  run(cb: () => void): void {}
  field: (x: T) => void = x => x;
}
class GenericChild extends Generic<number> {
  run() {
    return 1;
  }
  field = (x: number) => x;
}

// Intersections are not split: only unions are.
declare const taggedNumberFn: (() => number) & { tag: string };
declare const taggedVoidFn: (() => void) & { tag: string };
declare function runTagged(cb: (() => void) & { tag?: string }): void;
declare const taggedRunner: ((cb: () => void) => void) & { tag: string };
run(taggedNumberFn);
run(taggedVoidFn);
runTagged(() => 1);
runTagged(taggedNumberFn);
taggedRunner(() => 1);
const taggedTarget: (() => void) & { tag?: string } = () => 1;
