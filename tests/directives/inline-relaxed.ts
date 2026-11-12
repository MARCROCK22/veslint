// The notation of ESLint's first parser of configuration comments (levn) is looser than JSON: a
// text may have spaces and colons, a number may be written in any way JavaScript converts, and
// nothing at all is the number 0.
/* eslint @typescript-eslint/await-thenable: */
/* eslint @typescript-eslint/return-await: [2, in try catch] */
/* eslint @typescript-eslint/no-floating-promises: [0x2, {ignoreVoid: 0x0, ignoreIIFE: key: value}] */
/* eslint @typescript-eslint/no-array-delete: [1e0,, x y] */
/* eslint @typescript-eslint/no-for-in-array: (2) */
/* eslint @typescript-eslint/unbound-method: [2, {ignoreStatic: true, __proto__: {nope: 1}}] */
/* eslint @typescript-eslint/no-meaningless-void-operator: [2, {"checkNever": true} "x"] */
declare const p: Promise<number>;
declare const list: number[];
async function f() {
  p;
  await 1;
  delete list[0];
  for (const key in list) {
    void key;
  }
  void (void 0);
}
export { f };
