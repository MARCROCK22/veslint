// Reported.
class Box<T> {
  #value: T | undefined;
  get value(): T | undefined {
    if (this.#value === undefined) {
      return;
    }
  }
  static get empty(): Box<never> {
    console.log('none');
  }
  get [Symbol.toStringTag]() {}
}
const shape = {
  get area(): number {
    if (Math.random() > 0.5) {
      return 1;
    }
  },
};
Object.defineProperty(shape, 'size', {
  get: () => {
    console.log('size');
  },
});
Reflect.defineProperty(shape, 'name', {
  get: function named(): string {
    while (Math.random()) {
      return 'x';
    }
  },
});
Object.defineProperties(shape, {
  kind: {
    get() {
      return;
    },
  },
});
Object.create(null, {
  label: { get: (): void => {} },
});
// Not reported.
class Fine {
  get always(): number {
    throw new Error('never');
  }
  get either(): string {
    if (Math.random()) {
      return 'a';
    }
    return 'b';
  }
  set value(v: number) {}
}
interface WithGetter {
  get x(): number;
}
abstract class Shape {
  abstract get area(): number;
}
const plain = { get: () => 1 };
const arrowGetter = { get z() { return [1].map((n) => { n; }); } };
export { Box, shape, Fine, Shape, plain, arrowGetter };
export type { WithGetter };
