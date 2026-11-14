declare module 'virtual-pkg' {
  export function virtualSafe(): Promise<void>;
  export class VirtualPromise<T> extends Promise<T> {}
  export function virtualTask(): VirtualPromise<number>;
  export namespace Nested.Deeper {
    class DeepPromise<T> extends Promise<T> {}
    function deepTask(): DeepPromise<number>;
  }
  // typescript-eslint 8.72: a `global {}` inside the module is passed over, and what the module
  // exports through an alias counts too.
  global {
    class GlobalAugmentPromise<T> extends Promise<T> {}
    function globalAugmentTask(): GlobalAugmentPromise<number>;
  }
  import { OutsidePromise } from 'outside-mod';
  export { OutsidePromise };
}
declare module 'outside-mod' {
  export class OutsidePromise<T> extends Promise<T> {}
  export class UnexportedPromise<T> extends Promise<T> {}
  export function outsideTask(): OutsidePromise<number>;
  export function unexportedTask(): UnexportedPromise<number>;
}
