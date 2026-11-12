declare module 'virtual-pkg' {
  export function virtualSafe(): Promise<void>;
  export class VirtualPromise<T> extends Promise<T> {}
  export function virtualTask(): VirtualPromise<number>;
  export namespace Nested.Deeper {
    class DeepPromise<T> extends Promise<T> {}
    function deepTask(): DeepPromise<number>;
  }
}
