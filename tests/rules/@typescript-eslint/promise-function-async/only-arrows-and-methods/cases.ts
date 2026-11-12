// promise-function-async: functions that return promises and are not async.
declare const promise: Promise<string>;
declare const anyValue: any;
declare const unknownValue: unknown;
declare const flag: boolean;

function declared() {
  return promise;
}
function explicit(): Promise<string> {
  return promise;
}
async function alreadyAsync() {
  return promise;
}
function notPromise() {
  return 1;
}
function returnsAny() {
  return anyValue;
}
function returnsUnknown(): unknown {
  return unknownValue;
}
function hybridInferred() {
  return flag ? promise : 'text';
}
function hybridExplicit(): Promise<string> | string {
  return flag ? promise : 'text';
}
function allPromises(): Promise<string> | Promise<number> {
  return flag ? promise : Promise.resolve(1);
}
function nullablePromise(): Promise<string> | undefined {
  return flag ? promise : undefined;
}
function nullableInferred() {
  return flag ? promise : undefined;
}
function voidPromise(): Promise<void> {
  return Promise.resolve();
}
function* generator() {
  yield promise;
}
function overloaded(a: string): Promise<string>;
function overloaded(a: number): Promise<number>;
function overloaded(a: string | number): Promise<string | number> {
  return Promise.resolve(a);
}
function mixedOverloads(a: string): Promise<string>;
function mixedOverloads(a: number): number;
function mixedOverloads(a: string | number): Promise<string> | number {
  return typeof a === 'string' ? Promise.resolve(a) : a;
}
declare function ambient(): Promise<void>;
export default function () {
  return promise;
}
export function exported() {
  return promise;
}
function generic<T>(value: T): Promise<T> {
  return Promise.resolve(value);
}
function constrained<T extends Promise<unknown>>(value: T): T {
  return value;
}
function typeParameter<T>(value: T) {
  return value;
}

const expression = function () {
  return promise;
};
const named = function inner(): Promise<string> {
  return promise;
};
const arrow = () => promise;
const arrowBlock = () => {
  return promise;
};
const arrowAsync = async () => promise;
const arrowGeneric = <T,>(value: T) => Promise.resolve(value);
const arrowHybrid = () => (flag ? promise : 1);
const arrowTyped: () => Promise<string> = () => promise;
const curried = () => () => promise;
const iife = (function () {
  return promise;
})();
[1, 2].map(x => Promise.resolve(x));
[1, 2].map(function (x) {
  return Promise.resolve(x);
});
promise.then(() => promise);
new Promise<void>(resolve => resolve());

class Service {
  method() {
    return promise;
  }
  async asyncMethod() {
    return promise;
  }
  static staticMethod() {
    return promise;
  }
  public publicMethod(): Promise<string> {
    return promise;
  }
  private static privateStatic() {
    return promise;
  }
  protected override toString(): any {
    return promise;
  }
  get getter() {
    return promise;
  }
  set setter(value: Promise<string>) {}
  constructor() {
    void promise;
  }
  ['computed']() {
    return promise;
  }
  delete() {
    return promise;
  }
  static() {
    return promise;
  }
  'quoted'() {
    return promise;
  }
  123() {
    return promise;
  }
  #hidden() {
    return promise;
  }
  property = () => promise;
  functionProperty = function () {
    return promise;
  };
  static staticProperty = () => promise;
  overloadedMethod(a: string): Promise<string>;
  overloadedMethod(a: number): Promise<number>;
  overloadedMethod(a: any): Promise<any> {
    return Promise.resolve(a);
  }
  hybrid() {
    return flag ? promise : null;
  }
}
class Compact{method(){return promise}static other(){return promise}}
abstract class Shape {
  abstract load(): Promise<void>;
  save(): Promise<void> {
    return Promise.resolve();
  }
}
class Child extends Shape {
  override load() {
    return Promise.resolve();
  }
  public override save() {
    return Promise.resolve();
  }
}
function decorate(value: unknown, context: unknown) {}
class Decorated {
  @decorate
  method() {
    return promise;
  }
  @decorate static staticMethod() {
    return promise;
  }
  @decorate
  @decorate
  public multi() {
    return promise;
  }
}

const object = {
  method() {
    return promise;
  },
  property: function () {
    return promise;
  },
  arrow: () => promise,
  async asyncMethod() {
    return promise;
  },
  get getter() {
    return promise;
  },
  set setter(value: Promise<string>) {},
  ['computed']() {
    return promise;
  },
  *generator() {
    yield promise;
  },
};
const compact = {method(){return promise},other: 1};

// Thenables and subclasses.
class MyPromise<T> extends Promise<T> {}
interface PromiseLikeThing extends Promise<string> {
  extra: number;
}
interface Thenable {
  then(callback: () => void): void;
}
class Bluebird<T> {
  then(callback: (value: T) => void): void {}
}
declare const mine: MyPromise<string>;
declare const thing: PromiseLikeThing;
declare const thenable: Thenable;
declare const bluebird: Bluebird<number>;
declare const promiseLike: PromiseLike<string>;
function returnsSubclass() {
  return mine;
}
function returnsInterface() {
  return thing;
}
function returnsThenable() {
  return thenable;
}
function returnsBluebird(): Bluebird<number> {
  return bluebird;
}
function returnsPromiseLike() {
  return promiseLike;
}
function returnsIntersection(): Promise<string> & { extra: number } {
  return anyValue;
}
function returnsThenableOrPromise() {
  return flag ? thenable : promise;
}
type Alias = Promise<string>;
function returnsAlias(): Alias {
  return promise;
}
type Maybe = Promise<string> | string;
function returnsMaybe(): Maybe {
  return promise;
}
function returnsNever(): never {
  throw new Error('x');
}
function returnsAnyPromise(): Promise<any> {
  return anyValue;
}
function returnsAnyOrPromise() {
  return flag ? anyValue : promise;
}
function returnsUnknownOrPromise(): unknown | Promise<string> {
  return promise;
}
