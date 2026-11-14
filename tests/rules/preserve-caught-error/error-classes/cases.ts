declare function doSomething(): void;
class AppError extends Error {}
class MyError extends Error {
  constructor(a: string, b: string, options?: ErrorOptions) {
    super(a + b, options);
  }
}
class SimpleError extends Error {
  constructor(options?: ErrorOptions) {
    super('simple', options);
  }
}
declare const errors: { AppError: typeof AppError };

// Reported with errorClassNames: the cause at the argument position of each class.
try {
  doSomething();
} catch (err) {
  throw new AppError('failed');
}
try {
  doSomething();
} catch (err) {
  throw new MyError('a', 'b');
}
try {
  doSomething();
} catch (err) {
  throw new SimpleError();
}
try {
  doSomething();
} catch (err) {
  throw new errors.AppError(('failed'));
}
try {
  doSomething();
} catch (err) {
  throw new MyError(('a'), 'b',);
}

// Not reported.
try {
  doSomething();
} catch (err) {
  throw new AppError('failed', { cause: err });
}
try {
  doSomething();
} catch (err) {
  throw new MyError('a', 'b', { cause: err });
}
try {
  doSomething();
} catch (err) {
  throw new SimpleError({ cause: err });
}
