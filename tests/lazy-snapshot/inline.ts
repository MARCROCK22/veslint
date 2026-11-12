/* eslint @typescript-eslint/no-floating-promises: "error" */
// A comment turns on a rule that needs types: the snapshot is made for this file then.
declare function work(): Promise<void>;
work();
export class Other {
  method(): this {
    const self = this;
    return self;
  }
}
