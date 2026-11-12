// Shadowing in nested scopes: functions, blocks, catch clauses, loops, arrows and methods.
const outer = 1;
function shadowsInFunction() {
  const outer = 2;
  return outer;
}
{
  const outer = 3;
  void outer;
}
try {
  void 0;
} catch (outer) {
  void outer;
}
for (const outer of [1]) {
  void outer;
}
const arrow = (outer: number) => outer;
class WithMethod {
  method(outer: string) {
    return outer;
  }
  static staticMethod() {
    const outer = 4;
    return outer;
  }
}
function parameters(first: number, second = first) {
  return function inner(first: string) {
    return [first, second];
  };
}

// The name of a function or class expression on its own initializer.
var named = function named() {};
const conditional = Math.random() ? function conditional() {} : null;
const logical = null || class logical {};
const wrapped = String(function wrapped() {});
const inTest = (function inTest() {}) ? 1 : 2;

// Types and values with the same name.
type Shape = { kind: string };
function usesShape() {
  const Shape = 1;
  return Shape;
}
const value = 1;
function typed() {
  type value = string;
  const x: value = '';
  return x;
}
interface Merged {
  a: string;
}
function mergedInside() {
  interface Merged {
    b: string;
  }
  const m: Merged = { b: '' };
  return m;
}

// Function type parameters named like a value.
const param = 1;
type Callback = (param: string) => void;
type Constructor = new (param: string) => object;
interface Signatures {
  (param: string): void;
  new (param: string): Signatures;
  method(param: string): void;
}
declare function declared(param: string): void;
abstract class Overloads {
  overload(param: string): void;
  overload(param: string) {
    return param;
  }
  abstract abstractMethod(param: number): void;
}
type Shadow = (Shape: number) => void;

// Generics: a static method may reuse the class's type parameter name.
class Generic<T> {
  static create<T>(value: T) {
    return value;
  }
  method<T>(value: T) {
    return value;
  }
}
function genericFunction<T>() {
  return function inner<T>(value: T) {
    return value;
  };
}

// Type-only imports merged in a declared module.
import type { External } from 'external-module';
declare module 'external-module' {
  interface External {
    extra: string;
  }
  type Alias = External;
}
import { ValueImport } from 'value-module';
declare module 'value-module' {
  interface ValueImport {}
}

// Hoisting: a later declaration of the outer name.
function beforeFunction() {
  const later = 1;
  const laterType = 2;
  const laterVariable = 3;
  const laterClass = 4;
  return [later, laterType, laterVariable, laterClass];
}
function later() {}
type laterType = string;
let laterVariable = 5;
class laterClass {}

// Initializers and the calls in them (ignoreOnInitialization).
const initialized = [1].map(initialized => initialized);
const object = { run: () => [1].map(function (object) { return object; }) };
const deep = [1].filter(() => {
  const deep = 1;
  return deep;
});
const notInCall = () => {
  const notInCall = 1;
  return notInCall;
};
const [destructured = [1].map(destructured => destructured)] = [];
const method = [{ m(method: number) { return method; } }];

// Globals and lib names (builtinGlobals).
function shadowsGlobals() {
  const Object = 1;
  const Promise = 2;
  const name = 'x';
  const document = 3;
  return [Object, Promise, name, document];
}
const NaN = 0;

// Classes, enums and namespaces.
class Duplicate {
  method() {
    class Duplicate {}
    return Duplicate;
  }
}
enum Color {
  Red,
}
function enums() {
  const Color = 1;
  const Red = 2;
  return [Color, Red];
}
namespace Space {
  export const outer = 5;
  namespace Space {}
}

// `this` parameters and allowed names.
function withThis(this: Window) {
  return function nested(this: Window) {};
}
const allowed = 1;
function useAllowed() {
  const allowed = 2;
  return allowed;
}

// Global augmentations are ignored.
declare global {
  interface Window {
    outer: number;
  }
  var param: number;
}

export { Generic, Overloads, WithMethod, arrow, conditional, deep, destructured, genericFunction, initialized, logical, method, named, notInCall, object, parameters, shadowsGlobals, shadowsInFunction, typed, usesShape, mergedInside, withThis, useAllowed, beforeFunction, enums, inTest, wrapped, value };
export type { Callback, Constructor, Signatures, Shadow, External, ValueImport, laterType };
