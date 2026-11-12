// Cases of await-thenable where the answer depends on the node isThenableType is asked at
// (getTypeOfSymbolAtLocation): inside `then`, `cb` is the first parameter of the `then` of its own
// type, and where it is narrowed to a type without call signatures that `then` does not make it
// a thenable.
class Recursive {
  async then(cb: Recursive | (() => void)): Promise<void> {
    if (typeof cb === 'function') {
      return;
    }
    await cb;
    await (cb);
    await (cb as Recursive);
    const copy = cb;
    await copy;
    await Promise.all([cb, copy]);
    await Promise.race([cb]);
  }
}
declare const recursive: Recursive;
async function outside(): Promise<void> {
  await recursive;
  await Promise.all([recursive]);
}
void outside;
