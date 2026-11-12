// Cases of require-await where the answer depends on the node isThenableType is asked at
// (getTypeOfSymbolAtLocation): inside `then`, `cb` is the first parameter of the `then` of its own
// type, and where it is narrowed to a type without call signatures that `then` does not make it
// a thenable.
class Recursive {
  async then(cb: Recursive | (() => void)): Promise<unknown> {
    if (typeof cb === 'function') {
      return undefined;
    }
    return cb;
  }
  async parenthesized(cb: Recursive | (() => void)): Promise<unknown> {
    if (typeof cb === 'function') {
      return undefined;
    }
    return (cb);
  }
  async copied(cb: Recursive | (() => void)): Promise<unknown> {
    if (typeof cb === 'function') {
      return undefined;
    }
    const copy = cb;
    return copy;
  }
  async *yields(cb: Recursive | (() => void)): AsyncGenerator<unknown> {
    if (typeof cb !== 'function') {
      yield cb;
    }
  }
}
class Arrow {
  then(cb: Arrow | (() => void)): void {
    if (typeof cb !== 'function') {
      const arrow = async () => cb;
      const other = async (cb: Arrow) => cb;
      void [arrow, other];
    }
  }
}
void [Recursive, Arrow];
