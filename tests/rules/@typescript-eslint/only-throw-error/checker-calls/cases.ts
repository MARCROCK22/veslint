// Cases of only-throw-error where the answer depends on the node isThenableType is asked at
// (getTypeOfSymbolAtLocation): inside `then`, `cb` is the first parameter of the `then` of its own
// type, and where it is narrowed to a type without call signatures that `then` does not make it
// a thenable, so the handler of its `catch` does not rethrow.
class Recursive {
  catch(handler: (error: string) => void): void { void handler; }
  then(cb: Recursive | (() => void)): void {
    if (typeof cb === 'function') {
      return;
    }
    cb.catch(error => { throw error; });
    (cb).catch(error => { throw error; });
    const copy = cb;
    copy.catch(error => { throw error; });
  }
}
declare const recursive: Recursive;
recursive.catch(error => { throw error; });
