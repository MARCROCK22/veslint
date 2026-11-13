declare function work(): void;

// Reported.
try {
  work();
} catch (e) {
  throw new Error('failed');
}
try {
  work();
} catch (e) {
  throw new Error('failed', { cause: 'x' });
}
try {
  work();
} catch (e) {
  throw new TypeError('failed', {});
}
try {
  work();
} catch ({ message }) {
  throw new Error(message);
}
try {
  work();
} catch (e) {
  throw Error();
}
try {
  work();
} catch (e) {
  throw new AggregateError([]);
}
try {
  work();
} catch (e) {
  const fn = () => {
    const e = 1;
    throw new Error('x', { cause: e });
  };
}

// Not reported.
try {
  work();
} catch (e) {
  throw new Error('failed', { cause: e });
}
try {
  work();
} catch (e) {
  throw e;
}
try {
  work();
} catch {
  throw new Error('failed');
}
try {
  work();
} catch (e) {
  throw new Error('failed', options);
}
declare const options: ErrorOptions;
