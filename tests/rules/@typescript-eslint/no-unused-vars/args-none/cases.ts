/* global declaredGlobal, usedGlobal: writable, offGlobal: off */
usedGlobal = 1;

// Imports: unused ones get a suggestion (or a fix with enableAutofixRemoval.imports).
import UnusedDefault from 'm1';
import { unusedNamed } from 'm2';
import * as unusedNamespace from 'm3';
import DefaultUsed, { namedUnused1, namedUnused2 } from 'm4';
import DefaultUnused, { namedUsed } from 'm5';
import { first, second, third } from 'm6';
import { a7, b7 } from 'm7';
import type { OnlyType } from 'm8';
import { typeofOnly } from 'm9';
import equalsUnused = require('m10');
import Both1, { both2 } from 'm11';
import {
  multi1,
  multi2,
} from 'm12';
export { DefaultUsed, namedUsed, second, b7 };
type FromTypeof = typeof typeofOnly;

// Variables: defined, assigned, used only as a type, used by themselves.
const unusedConst = 1;
let assigned = 1;
assigned = 2;
let incremented = 0;
incremented++;
let selfAssigned = 0;
selfAssigned = selfAssigned + 1;
let compound = 1;
compound += 1;
const onlyAsType = { a: 1 };
type UsesTypeof = typeof onlyAsType;
const usedConst = 1;
console.log(usedConst);
var _ignoredVar = 1;
const _usedIgnored = 2;
console.log(_usedIgnored);
let inLoop = 0;
for (const item of [1, 2]) {
  inLoop = item;
}
let laterRead = 0;
function writesLater() {
  laterRead = 1;
}
writesLater();

// Functions and parameters.
function unusedFunction() {}
function recursive(n: number): number {
  return recursive(n - 1);
}
function afterUsed(a: number, b: number, c: number) {
  return b;
}
function allUnused(x: number, _y: number) {}
function withDefault(d = 1, e: number) {
  return e;
}
function destructured({ p, q }: { p: number; q: number }, [r, _s]: number[]) {
  return p;
}
function rest(...args: number[]) {}
const arrow = (v: number, w: number) => w;
arrow(1, 2);
afterUsed(1, 2, 3);
allUnused(1, 2);
withDefault(1, 2);
destructured({ p: 1, q: 2 }, [1, 2]);
rest();
class WithMembers {
  constructor(private secret: number, unusedParam: number, public visible: number) {}
  set value(v: number) {}
  method(this: WithMembers, used: number, unused: number) {
    return used;
  }
}
new WithMembers(1, 2, 3);
declare function declared(param: number): void;
type Fn = (param: number) => void;
interface Sig {
  method(param: number): void;
}

// Catch clauses.
try {
  void 0;
} catch (error) {}
try {
  void 0;
} catch (_ignoredError) {}
try {
  void 0;
} catch ({ message }) {}

// Destructuring: rest siblings and arrays.
const { kept, dropped, ...others } = { kept: 1, dropped: 2, more: 3 };
console.log(kept, others);
const { alone } = { alone: 1 };
const [arrayFirst, _arraySecond, arrayThird] = [1, 2, 3];
console.log(arrayThird);
let reassignedArray = 0;
[reassignedArray] = [1];
let restTarget = 0;
let restOthers = {};
({ restTarget, ...restOthers } = { restTarget: 1 });
console.log(restOthers);

// Classes, enums, namespaces and types.
class UnusedClass {}
class WithStaticBlock {
  static {
    console.log('side effect');
  }
}
class SelfUse {
  static create() {
    return new SelfUse();
  }
}
enum UnusedEnum {
  A,
}
namespace UnusedNamespace {
  export const inner = 1;
}
type UnusedType = string;
interface UnusedInterface {
  recursive: UnusedInterface;
}
type Mapped = { [K in 'a']: number };
export type { Mapped };

// `using` declarations.
function resources() {
  using resource = { [Symbol.dispose]() {} };
}
resources();

// Declared namespaces and modules: their declarations are exported.
declare namespace Ambient {
  const declaredConst: number;
  function declaredFunction(): void;
  namespace Nested {
    interface Deep {}
  }
}
declare module 'ambient-module' {
  interface Augmented {}
  type Overridden = number;
}
declare module 'with-export' {
  interface Hidden {}
  export {};
}
declare global {
  interface GlobalAugmentation {}
}

// Every identifier inside the parameters of a signature or a setter counts as a use: the names of
// its type annotation (also a key of a type literal), not those of its return type.
const inSignature = 1;
type SignatureParam = (value: typeof inSignature) => void;
const inReturn = 1;
type SignatureReturn = (value: number) => typeof inReturn;
const key = 1;
type KeyInParam = (options: { key: string }) => void;
const inSetter = 1;
class Setter {
  set value(v: typeof inSetter) {}
}
export type { SignatureParam, SignatureReturn, KeyInParam };
export { Setter };

// For-in with a return.
function hasKeys(object: object) {
  for (const key in object) {
    return true;
  }
  return false;
}
hasKeys({});

export {};
