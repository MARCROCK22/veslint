// With experimentalDecorators and emitDecoratorMetadata, a file with a decorator is left alone,
// except for `import()` types.
import Foo from 'b1';
import { Bar, Baz } from 'b2';
declare function deco(target: unknown): void;
@deco
class Decorated {
  constructor(foo: Foo, bar: Bar) {}
}
Baz();
let annotation: import('b3').T;
export { Decorated, annotation };
