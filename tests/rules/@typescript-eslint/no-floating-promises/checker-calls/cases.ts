// Cases of no-floating-promises with checkThenables where the answer depends on the node the types
// of `then` and of its parameters are asked at (getTypeOfSymbolAtLocation): inside `then`, `cb`
// and `err` are the parameters of the `then` of their own type, and where one is narrowed to a
// type without call signatures that `then` does not make it a thenable.
class Recursive {
  then(cb: Recursive | (() => void), err: Recursive | (() => void)): void {
    if (typeof cb === 'function' || typeof err === 'function') {
      return;
    }
    cb;
    (cb);
    err;
    const copy = cb;
    copy;
    [cb];
    [copy];
    cb as Recursive;
  }
}
declare const recursive: Recursive;
recursive;
[recursive];
