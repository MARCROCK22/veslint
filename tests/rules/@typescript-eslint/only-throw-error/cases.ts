declare const anyValue: any;
declare const unknownValue: unknown;
declare const maybeError: Error | undefined;
declare const errorOrString: Error | string;
declare const cond: boolean;
declare const none: [];
class CustomError extends Error {}
interface ErrorShape extends Error {
  code: number;
}
declare const shaped: ErrorShape;
declare const promise: Promise<number>;
declare const notPromise: { catch(f: (e: any) => void): void; then: number };
function work(): void {}

function f1() {
  throw new Error('x');
}
function f2() {
  throw new CustomError();
}
function f3() {
  throw 'text';
}
function f4() {
  throw 5;
}
function f5() {
  throw undefined;
}
function f6() {
  throw null;
}
function f7() {
  throw anyValue;
}
function f8() {
  throw unknownValue;
}
function f9() {
  throw maybeError;
}
function f10() {
  throw errorOrString;
}
function f11() {
  throw { message: 'x' };
}
function f12() {
  throw (new Error('x'));
}
function f13() {
  throw ('text');
}
function f14() {
  throw void 0;
}
function f15<T extends Error>(t: T) {
  throw t;
}
function f16<T>(t: T) {
  throw t;
}
function f17() {
  throw Object.assign(new Error('x'), { code: 1 });
}
function f18() {
  throw new Error('x') as Error | string;
}
function f19() {
  throw undefined as undefined | Error;
}
function f20() {
  throw shaped;
}
function f21() {
  throw (0, 'sequence');
}
function f22() {
  throw cond ? new Error('x') : 'text';
}
function f23() {
  throw Error;
}
function f24() {
  throw NaN;
}

function r1() {
  try {
    work();
  } catch (e) {
    throw e;
  }
}
function r2() {
  try {
    work();
  } catch (e: any) {
    throw e;
  }
}
function r3() {
  try {
    work();
  } catch ({ message }) {
    throw message;
  }
}
function r4() {
  try {
    work();
  } catch (e) {
    const copy = e as string;
    throw copy;
  }
}
function r5() {
  try {
    work();
  } catch (e) {
    e = 'text';
    throw e;
  }
}
function r6() {
  try {
    work();
  } catch (e) {
    throw (e);
  }
}
function r7() {
  try {
    work();
  } catch (e) {
    throw e as string;
  }
}
function r8() {
  try {
    work();
  } catch (e) {
    (() => {
      throw e;
    })();
  }
}
function r9(e: string) {
  try {
    work();
  } catch {
    throw e;
  }
}

promise.catch(e => {
  throw e;
});
promise.catch((e: string) => {
  throw e;
});
promise.then(
  v => v,
  (e: string) => {
    throw e;
  },
);
promise.then(e => {
  throw e;
});
promise.catch(function (e: string) {
  throw e;
});
promise.catch((e: string = 'x') => {
  throw e;
});
promise.catch(({ message }: { message: string }) => {
  throw message;
});
promise.catch((...args: string[]) => {
  throw args;
});
promise.catch((first: unknown, e: string) => {
  throw e;
});
notPromise.catch((e: string) => {
  throw e;
});
promise?.catch((e: string) => {
  throw e;
});
(promise?.catch)((e: string) => {
  throw e;
});
(promise.catch)((e: string) => {
  throw e;
});
promise['catch']((e: string) => {
  throw e;
});
promise.catch(
  ...[
    (e: string) => {
      throw e;
    },
  ],
);
promise.catch(
  cond
    ? (e: string) => {
        throw e;
      }
    : undefined,
);
promise.catch(((e: string) => {
  throw e;
}));
((e: string) => {
  throw e;
})('x');
promise.catch((e: string) => {
  const inner = () => {
    throw e;
  };
  inner();
});
promise.then(undefined, (e: string) => {
  throw e;
});
promise.then(...none, (e: string) => {
  throw e;
});
promise.then(v => v, (e?: string) => {
  throw e;
});
promise.finally(() => {
  throw 'finally';
});
