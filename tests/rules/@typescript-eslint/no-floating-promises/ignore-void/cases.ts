// ignoreVoid: false. `void` does not handle a promise: what is inside it is checked, and the
// messages are the ones without "void".
declare const p: Promise<number>;
declare const maybe: { run?: () => Promise<number> } | undefined;
declare const list: Promise<number>[];
async function f() {
  void p;
  void (p);
  void p.then(() => {});
  void p.catch(() => {});
  void p.then(() => {}, null);
  void maybe?.run?.();
  void (maybe?.run)?.();
  void list;
  void [p, p];
  void (1, p);
  void void p;
  void 0;
  void (await p);
  p;
  p.catch(null);
  list;
  void (p ? p : 1);
  void (p || 1);
}
export { f };
