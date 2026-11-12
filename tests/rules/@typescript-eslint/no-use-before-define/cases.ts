// Variables used before their declaration, in the same scope and from an inner one.
alpha;
var alpha = 1;
let beta = 2;
beta;
function readsLater() {
  return gamma + delta;
}
const gamma = 3;
let delta = 4;
{
  epsilon;
  let epsilon = 5;
}

// In the initializer of the variable itself.
var selfInit = selfInit;
const [arrayDefault = arrayDefault] = [];
const { objectDefault = objectDefault } = {} as { objectDefault?: number };
const { renamed: renamedTarget = renamedTarget } = {} as { renamed?: number };
for (var forIn in forIn) {
}
for (const forOf of forOf) {
}
function parameterDefault(first = first, second = third, third = 1) {
  return [first, second, third];
}
const later = (value = laterValue) => value;
const laterValue = 1;
const viaFunction = () => viaFunction;
const viaParens = (viaParens);
let annotated: typeof annotated = 1;
const typedSelf: number = typedSelf;

// Functions and classes.
hoisted();
function hoisted() {}
new Before();
class Before {}
function makesLater() {
  return new After();
}
class After {}
const OuterUse = () => InnerLater;
class InnerLater {}
@decorate(Decorated)
class Decorated {}
@decorate(ExportedDecorated)
export class ExportedDecorated {}
export @decorate(ExportedAfter) class ExportedAfter {}
@decorate(NotTheClass)
class Other {}
const NotTheClass = 1;
declare function decorate(value: unknown): <T>(target: T) => T;
const expression = class Named {
  method() {
    return Named;
  }
};

// Enums.
Same.a;
enum Same {
  a,
}
function readsEnum() {
  return Later.b;
}
enum Later {
  b,
}
enum SelfReference {
  x = 1,
  y = x,
  z = SelfReference.x,
}

// Types: references, `typeof` and type queries in annotations.
let typed: LaterType;
type LaterType = string;
interface UsesLater {
  value: AlsoLater;
}
interface AlsoLater {}
type Query = typeof queried;
const queried = 1;
type QueryMember = typeof queriedObject.member;
const queriedObject = { member: 1 };
function generic<T extends Constraint>(value: T): T {
  return value;
}
interface Constraint {}
let asserted = 1 as unknown as AssertedType;
type AssertedType = number;

// Function types: a parameter's type that names a later value.
type Callback = (value: typeof callbackValue) => void;
const callbackValue = 1;

// Named exports.
export { exported };
const exported = 1;
export { renamedExport as other };
const renamedExport = 1;
export { undeclaredName };
export type { LaterExportType };
type LaterExportType = number;
export default defaultLater;
const defaultLater = 1;

// Namespaces and declared things.
namespace Space {
  export const inner = later2;
  const later2 = 1;
}
Space.inner;
declare const declared: number;
declared;

// Labels, properties and keys are not references.
const object = { key: 1, [computedKey]: 2 };
const computedKey = 'k';
object.key;

// Class members.
class Members {
  field = memberLater;
  static staticField = staticLater;
  method() {
    return methodLater;
  }
}
const memberLater = 1;
const staticLater = 1;
const methodLater = 1;
new Members();

// Closures.
function outer() {
  inner();
  function inner() {}
  return innerArrow;
  const innerArrow = () => 1;
}
outer();
