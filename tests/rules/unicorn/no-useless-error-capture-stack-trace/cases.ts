// unicorn/no-useless-error-capture-stack-trace: a subclass of a built-in error already captures its
// stack trace; `Error.captureStackTrace(this, …)` in its constructor does nothing more.
export class MyError extends Error {
  constructor(message: string) {
    super(message);
    Error.captureStackTrace(this, MyError);
  }
}
export class TargetError extends TypeError {
  constructor() {
    super();
    Error.captureStackTrace(this, new.target);
  }
}
export class ConstructorError extends RangeError {
  constructor() {
    super();
    Error.captureStackTrace(this, this.constructor);
  }
}
export const Expression = class Named extends Error {
  constructor() {
    super();
    if (true) Error.captureStackTrace(this, Named);
  }
};

// Not reported.
export class Other extends Error {
  constructor() {
    super();
    Error.captureStackTrace(this, Other.prototype.constructor);
    Error.captureStackTrace(this);
    Error.captureStackTrace({}, Other);
    function inner(this: unknown) {
      Error.captureStackTrace(this, Other);
    }
    inner;
  }
  method() {
    Error.captureStackTrace(this, Other);
  }
}
class Base {}
export class NotAnError extends Base {
  constructor() {
    super();
    Error.captureStackTrace(this, NotAnError);
  }
}
