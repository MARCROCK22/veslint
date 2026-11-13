// unicorn/custom-error-definition: a subclass of an error is named `…Error`, calls `super()` with
// the message, and sets `name` to its own name.
declare const exports: Record<string, unknown>;
declare const errors: { BaseError: ErrorConstructor };

export class fooError extends Error {
  name = 'fooError';
}
export class Foo extends Error {
  name = 'Foo';
}
export class NoNameError extends Error {}
export class EmptyNameError extends Error {
  name;
}
export class WrongNameError extends Error {
  name = 'Other';
}
export class NoSuperError extends Error {
  constructor() {
    this.name = 'NoSuperError';
  }
}
export class MessageError extends Error {
  constructor(message: string) {
    super();
    this.message = message;
    this.name = 'MessageError';
  }
}
export class NameInConstructorError extends TypeError {
  constructor() {
    super('message');
    this.name = 'Other';
  }
}
export class NoNameInConstructorError extends errors.BaseError {
  constructor() {
    super('message');
  }
}
exports.Other = class ExportedError extends Error {
  name = 'ExportedError';
};
exports['x'] = class SecondError extends Error {
  name = 'SecondError';
};

// Not reported.
export class GoodError extends Error {
  name = 'GoodError';
}
export class AlsoGoodError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'AlsoGoodError';
  }
}
export class Plain extends Array {}
exports.SameError = class SameError extends Error {
  name = 'SameError';
};
