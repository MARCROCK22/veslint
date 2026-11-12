// Cases of no-misused-promises where the answer depends on the exact call typescript-eslint makes
// to the checker: getTypeOfSymbolAtLocation, getContextualTypeForArgumentAtIndex and
// `symbol.members`.
declare function task(): Promise<number>;

// getTypeOfSymbolAtLocation(param, node): inside `then`, `cb` is the first parameter of the `then`
// of its own type, and where it is narrowed to a type without call signatures that `then` does
// not make it a thenable.
class Recursive {
  then(cb: Recursive | (() => void)): void {
    if (typeof cb === 'function') {
      return;
    }
    if (cb) {}
    if ((cb)) {}
    const spread = { ...cb };
    const copy = cb;
    if (copy) {}
    void [spread];
  }
}
declare const recursive: Recursive;
if (recursive) {}

// The same with the parameter of the callee: `handler` is narrowed where it is called.
declare function isVoidHandler(x: unknown): x is (cb: () => void) => void;
function callsItself(handler: ((cb: () => void) => void) | ((cb: () => Promise<void>) => void)): void {
  handler(async () => {});
  if (isVoidHandler(handler)) {
    handler(async () => {});
    (handler)(async () => {});
  }
}

// getContextualTypeForArgumentAtIndex counts the arguments as written: a spread of a tuple before
// an argument does not shift it.
declare function fixed(a: number, b: string, cb: () => void): void;
declare function fixedLate(a: number, cb: () => void, last: () => void): void;
declare function fixedFirst(cb: () => void, a: number, b: string): void;
declare function withRestTuple(a: number, ...rest: [x: string, cb: () => void]): void;
declare function withRestArray(a: number, ...cbs: Array<() => void>): void;
declare function withOptionalTuple(...rest: [a: number, b?: string, cb?: () => void]): void;
declare function withOpenTuple(...rest: [a: number, ...cbs: Array<() => void>]): void;
declare function withBothKinds(a: number, cb: (() => void) | (() => Promise<void>)): void;
declare function generic<T extends unknown[]>(cb: () => void, ...rest: T): void;
declare function overloaded(a: number, b: string, cb: () => void): void;
declare function overloaded(a: number, cb: () => Promise<void>): void;
declare const pair: [number, string];
declare const single: [number];
declare const none: [];
declare const numbers: number[];
declare const callbacks: Array<() => void>;
declare const callbackPair: [() => void, () => void];
declare const anyValue: any;

fixed(...pair, async () => {});
fixed(1, 's', async () => {});
fixed(...single, 's', async () => {});
fixed(...none, 1, 's', async () => {});
fixed(...single, async () => {}, async () => {});
fixedLate(...pair, async () => {});
fixedLate(...single, async () => {}, async () => {});
fixedLate(...numbers, async () => {});
fixedLate(...numbers, async () => {}, async () => {});
fixedFirst(async () => {}, ...pair);
fixedFirst(...callbackPair, async () => {});
withRestTuple(...pair, async () => {});
withRestTuple(...single, async () => {});
withRestTuple(...single, 's', async () => {});
withRestTuple(1, ...['s'] as [string], async () => {});
withRestArray(...single, async () => {});
withRestArray(...pair, async () => {});
withRestArray(...none, async () => {}, async () => {});
withRestArray(1, ...callbacks, async () => {});
withRestArray(...anyValue, async () => {});
withOptionalTuple(...single, async () => {});
withOptionalTuple(...pair, async () => {});
withOptionalTuple(...none, 1, 's', async () => {});
withOptionalTuple(...single, 's', async () => {}, async () => {});
withOpenTuple(...single, async () => {});
withOpenTuple(...pair, async () => {});
withOpenTuple(...none, async () => {}, async () => {});
withBothKinds(...single, async () => {});
generic(async () => {}, ...pair);
generic(...callbackPair, async () => {});
generic(...none, async () => {}, async () => {});
overloaded(...pair, async () => {});
overloaded(...single, async () => {});
new Promise<void>(...([async resolve => { resolve(); }] as [(resolve: () => void) => void]));
function forwards<U extends Array<() => void>>(...xs: U): void {
  generic(...xs, async () => {});
  withRestArray(1, ...xs, async () => {});
}

// `symbol.members`: what the symbol of the heritage type declares, not instantiated, and its
// type parameters too.
interface Root { hidden(): void; shown(): void }
interface WithTypeParameter<hidden> extends Root { own(): void }
class HiddenByTypeParameter implements WithTypeParameter<string> {
  async hidden() {}
  async shown() {}
  async own() {}
}
type Literal<T> = { generic(): T; fixed(): void };
class ViaLiteral implements Literal<void> {
  async generic() {}
  async fixed() {}
}
interface Generic<T> { generic(): T; fixed(): void }
class ViaGeneric implements Generic<void> {
  async generic() {}
  async fixed() {}
}
class ViaRecord implements Record<'mapped', () => void> {
  async mapped() {}
}
type Both = { left(): void } & { right(): void };
class ViaIntersection implements Both {
  async left() {}
  async right() {}
}
interface Names { 'quoted'(): void; 1(): void; __under(): void; ___three(): void; ['computed'](): void }
class ViaNames implements Names {
  async 'quoted'() {}
  async 1() {}
  async __under() {}
  async ___three() {}
  async ['computed']() {}
}
class WithStatic { inherited(): void {} static shared(): void {} }
class ViaClass extends WithStatic {
  async inherited() {}
  async shared() {}
}
declare function mixin(): new () => { mixed(): void };
class ViaMixin extends mixin() {
  async mixed() {}
}
class Merged { fromClass(): void {} }
interface Merged { fromInterface(): void }
class ViaMerged extends Merged {
  async fromClass() {}
  async fromInterface() {}
}
interface Properties { property: () => void; optional?: () => void }
class ViaProperties implements Properties {
  property = async () => {};
  optional = async () => {};
}
interface WithConstructorMethod { constructor(): void }
interface ViaConstructorMethod extends WithConstructorMethod { constructor(): Promise<void> }
class Deep extends ViaGeneric {
  async fixed() {}
}

// getTypeOfSymbolAtLocation(propertySymbol, tsNode.name): methods of object literals.
interface Handlers { onRun(): void; onStop?: () => void; 'on-quoted': () => void }
const handlers: Handlers = {
  async onRun() {},
  async onStop() {},
  async 'on-quoted'() {},
};

void [task, callsItself, forwards, handlers];
void [HiddenByTypeParameter, ViaLiteral, ViaGeneric, ViaRecord, ViaIntersection, ViaNames, ViaClass];
void [ViaMixin, ViaMerged, ViaProperties, Deep];
export type { ViaConstructorMethod };

// The constructor of a class has no name; an interface method named like it does.
class WithConstructor { constructor() {} }
class ViaConstructor extends WithConstructor implements WithConstructorMethod {
  constructor() { super(); }
}
abstract class AbstractConstructor implements WithConstructorMethod {
  constructor();
  constructor(x?: number) { void x; }
}
void [ViaConstructor, AbstractConstructor];

// After a spread, the contextual type of an argument where the checker makes a type: a generic rest
// parameter, a union of rest tuples, and the elements around the rest element of a tuple
// (TypeScript 7.1 answers getContextualTypeForArgumentAtIndex itself).
declare function genericRest<T extends Array<() => void>>(a: number, ...rest: T): void;
declare function unionRest(...rest: [number, () => void] | [number, string, () => void]): void;
declare function middleRest(...rest: [number, ...Array<() => void>, () => void]): void;
declare function middleRestTail(...rest: [number, ...string[], () => void]): void;
genericRest(...single, async () => {});
genericRest(1, ...callbacks, async () => {});
unionRest(...single, async () => {});
unionRest(...pair, async () => {});
middleRest(...single, async () => {}, async () => {});
middleRestTail(...single, 's', async () => {});
