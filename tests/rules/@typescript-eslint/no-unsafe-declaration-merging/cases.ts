// no-unsafe-declaration-merging: a class and an interface that declare the same name in the same
// scope. Both names are reported.
interface A1 {}
class A1 {}

class A2 {}
interface A2 {}

// abstract, declared and exported forms.
abstract class A3 {}
interface A3 {}
declare class A4 {}
declare interface A4 {}
export class A5 {}
export interface A5 {}
export default class A6 {}
interface A6 {}

// An interface with type parameters has a scope of its own, so only the class is reported.
interface A7<T> {
  value: T;
}
class A7<T> {}
class A8<T> {}
interface A8<T> {
  value: T;
}

// Three declarations.
interface A9 {}
class A9 {}
interface A9 {}

// Inside functions, blocks, namespaces and `declare global`.
function f1() {
  interface B1 {}
  class B1 {}
  return B1;
}
{
  interface B2 {}
  class B2 {}
}
namespace N1 {
  export interface B3 {}
  export class B3 {}
}
declare global {
  interface B4 {}
  class B4 {}
}
declare module 'merging-module' {
  interface B5 {}
  class B5 {}
}

// Not merged with a class and an interface in one scope.
interface C1 {}
class C2 implements C1 {}
namespace C3 {}
namespace C3 {}
enum C4 {}
namespace C4 {}
function C5() {}
namespace C5 {}
class C6 {}
namespace C6 {}
function C7() {}
interface C7 {}
const C8 = class C8 {};
interface C8 {}
interface C9 {}
function f2() {
  return class C9 {};
}
interface C10 {}
(function () {
  class C10 {}
})();
namespace N2 {
  interface C11 {}
}
class C11 {}
interface C12 {}
interface C12 {}
class C13 {}
declare namespace C13 {}

export { f1, f2, C2, C5, C6, C7, C8, C11, C13 };
