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

// Only a descriptor in its place, for the global Object and Reflect (10.15.0).
declare const target: object;
Object.defineProperty(target, 'a', { get() {} });
Reflect.defineProperty(target, 'a', { get: function () {} });
Object.defineProperties(target, { a: { get() {} } });
Object.create(target, { a: { get: () => {} } });
Object?.defineProperty(target, 'a', { get() {} });
Object.defineProperty({ get() {} }, 'a', { value: 1 });
Object.defineProperties({ a: { get() {} } }, { b: { value: 1 } });
Object.create({ a: { get() {} } }, { b: { value: 1 } });
function shadowObject(Object: any) {
  Object.defineProperty(target, 'a', { get() {} });
}
