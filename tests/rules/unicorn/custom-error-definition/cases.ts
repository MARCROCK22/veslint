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

// 79.0.0: error options, `message` accessors, TypeScript wrappers of the base class.
export class OptionsMissingError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'OptionsMissingError';
  }
}
export class OptionsFirstError extends Error {
  constructor(options?: ErrorOptions) {
    super(undefined);
    this.name = 'OptionsFirstError';
  }
}
export class StatusError extends Error {
  constructor(status: number, message: string) {
    super(message);
    this.name = 'StatusError';
  }
}
export class NoMessageError extends Error {
  constructor(message: string, options?: ErrorOptions) {
    super(undefined, options);
    this.name = 'NoMessageError';
  }
}
export class NoOptionsError extends Error {
  constructor(message: string, options?: ErrorOptions) {
    super(message);
    this.name = 'NoOptionsError';
  }
}
export class InlineCauseError extends Error {
  constructor(cause: unknown) {
    super('Fixed message', { cause });
    this.name = 'InlineCauseError';
  }
}
export class AccessorError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'AccessorError';
  }
  get message() {
    return 'x';
  }
}
export class GetterOnlyError extends Error {
  constructor(message: string) {
    super();
    this.message = message;
    this.name = 'GetterOnlyError';
  }
  // @ts-expect-error -- a getter over the property
  get message() {
    return 'x';
  }
}
export class AssignedMessageError extends Error {
  constructor(message: string) {
    super();
    this.message = message;
    this.name = 'AssignedMessageError';
  }
}
export class WrappedBaseError extends (Error as ErrorConstructor) {
  constructor(message: string, options?: ErrorOptions) {
    super(message, options);
    this.name = 'WrappedBaseError';
  }
}
export class FieldNameError extends Error {
  name = 'Other' as const;
}
export class EmptyNameError extends Error {
}
export abstract class AbstractError extends Error {}
export class AggregatedError extends AggregateError {
  constructor(errors: unknown[]) {
    super(errors);
    this.name = 'AggregatedError';
  }
}
