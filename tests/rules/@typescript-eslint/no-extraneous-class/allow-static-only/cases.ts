// no-extraneous-class with its default options: a class without a superclass that is empty, has
// only a constructor (without parameter properties), or only static members, is reported at its
// name (a declaration) or at the class (an expression, or an anonymous default export).
declare function dec(target: unknown): void;
declare const Base: new () => object;
interface I {}

class Empty {}
class WithComment {
  // only a comment
}
class Semicolons {
  ;
}
class OnlyConstructor {
  constructor() {}
}
class OnlyConstructorOverloads {
  constructor(a: string);
  constructor(a?: string) {}
}
class StringConstructor {
  'constructor'() {}
}
class ParameterProperty {
  constructor(private a: string) {}
}
class ReadonlyParameter {
  constructor(readonly a: string) {}
}
class OnlyStatic {
  static a = 1;
  static b() {}
  static get c() {
    return 1;
  }
  static accessor d = 1;
  static {}
}
class StaticBlock {
  static {}
}
class StaticConstructor {
  static constructor() {}
}
class StaticAndConstructor {
  static a = 1;
  constructor() {}
}
class StaticAndParameterProperty {
  static a = 1;
  constructor(public b: string) {}
}
class StaticAndInstance {
  static a = 1;
  b = 2;
}
class WithIndex {
  [key: string]: unknown;
}
abstract class AbstractProperty {
  abstract a: string;
}
abstract class AbstractMethod {
  abstract m(): void;
}
abstract class AbstractAccessor {
  abstract accessor q: string;
}
abstract class AbstractStatic {
  static a: string;
}
class Accessor {
  accessor p = 1;
}
class Sub extends Base {}
class Impl implements I {}
const expression = class {};
const named = class Named {};
const staticExpression = class {
  static a = 1;
};
@dec
class Decorated {}
@dec
export class ExportedDecorated {}
export class Exported {
  static x = 1;
}
declare class Declared {}
export default class {}
function nested() {
  class Inner {}
  return class {
    constructor() {}
  };
}
