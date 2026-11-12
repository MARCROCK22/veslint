// Cases of return-await where the answer depends on the node needsToBeAwaited is asked at
// (getTypeOfSymbolAtLocation): inside `then`, `cb` is the first parameter of the `then` of its own
// type, and where it is narrowed to a type without call signatures that `then` does not make it
// a thenable.
class Recursive {
  async then(cb: Recursive | (() => void)): Promise<unknown> {
    if (typeof cb === 'function') {
      return undefined;
    }
    try {
      if (Math.random() > 0.5) {
        return cb;
      }
      if (Math.random() > 0.5) {
        return (cb);
      }
      if (Math.random() > 0.5) {
        return await cb;
      }
      const copy = cb;
      return copy;
    } catch {
      return undefined;
    }
  }
}
void Recursive;
