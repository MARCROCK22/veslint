// The same code under the configuration of each folder.
declare const p: Promise<number>;
declare const list: number[];
async function f() {
  p;
  void p;
  await 1;
  delete list[0];
  // eslint-disable-next-line @typescript-eslint/no-floating-promises
  p;
  // eslint-disable-next-line @typescript-eslint/no-array-delete
  await 2;
  // eslint-disable-next-line
  void 0;
}
export { f };
