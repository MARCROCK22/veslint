// naming-convention with the `unused` modifier: what nothing uses must start with `_`.
import type { Shape } from './module';
import unusedDefault, { named_import } from './module';
declare const items: number[];
declare function call(...args: unknown[]): void;

const usedConst = 1;
const unusedConst = 2;
const _unusedConst = 3;
let onlyWritten = 1;
onlyWritten = 2;
let selfUpdated = 1;
selfUpdated++;
let selfAssigned = 1;
selfAssigned = selfAssigned + 1;
let compound = 1;
compound += 2;
let logicalAssigned: number | undefined;
logicalAssigned ??= 1;
let readInSequence = 1;
call((readInSequence = 2, readInSequence));
let readLater = 1;
readLater = readLater * 2;
call(readLater);
const typeofOnly = 1;
type TypeofUser = typeof typeofOnly;
export const exportedConst = 1;
const laterExported = 1;
export { laterExported };
const { usedProperty, unusedProperty, ...unusedRest } = { usedProperty: 1, unusedProperty: 2, extra: 3 };
const [usedElement, unusedElement] = items;
call(usedConst, usedProperty, usedElement, named_import);
let storedCallback = () => {};
storedCallback = () => call(storedCallback);
let inLoop = 0;
for (const item of items) {
  inLoop = item;
}
for (const key in { a: 1 }) {
}
function loopReturn() {
  for (const unusedKey in { a: 1 }) return true;
  return false;
}

function usedFunction(usedParam: number, unusedParam: number, _ignored: number) {
  return usedParam;
}
function unusedFunction() {}
function _unusedFunction() {}
function recursiveOnly(): void {
  recursiveOnly();
}
const recursiveArrow = (): void => recursiveArrow();
export function exportedFunction(first: number, unusedSecond: number) {
  return first;
}
function withThis(this: Window, unusedValue: string) {}
function isShape(value: unknown, unusedOther: unknown): value is Shape {
  return true;
}
function assertsIt(value: unknown): asserts value {}
declare function declaredFunction(signatureParam: string): void;
type FunctionType = (typeParam: string) => void;
interface Signatures {
  (callParam: string): void;
  method(methodParam: string): void;
}
call(usedFunction, withThis, isShape, assertsIt, loopReturn);

class UsedClass {
  constructor(private propertyParam: string, plainUnused: string) {}
  set value(setterParam: number) {}
  method(methodUnused: string, methodUsed: string) {
    return methodUsed;
  }
}
class UnusedClass {}
class _UnusedClass {}
class SelfReferenced {
  clone(): SelfReferenced {
    return new SelfReferenced();
  }
}
export class ExportedClass {}
call(UsedClass);

enum UsedEnum {
  A,
  B,
}
enum UnusedEnum {
  C,
}
enum SelfEnum {
  D = 1,
  E = SelfEnum.D,
}
call(UsedEnum.A);
interface UsedInterface {}
interface UnusedInterface {}
interface SelfInterface {
  next: SelfInterface;
}
type UsedAlias = UsedInterface;
type UnusedAlias = string;
type SelfAlias = { next: SelfAlias };
export type ExportedAlias = UsedAlias;
function generic<Used, Unused>(value: Used): Used {
  return value;
}
type GenericAlias<UsedParam, UnusedParam> = UsedParam[];
type Mapped<T> = { [Key in keyof T]: number };
call(generic);
namespace UnusedNamespace {
  export const inner = 1;
}
try {
} catch (unusedError) {}
