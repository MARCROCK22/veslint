// `/* eslint … */` comments change the rules of this file.
/* eslint @typescript-eslint/no-floating-promises: "off" */
/* eslint @typescript-eslint/await-thenable: 2, @typescript-eslint/no-array-delete: [1] */
/* eslint @typescript-eslint/no-for-in-array: "error" */
/* eslint @typescript-eslint/no-floating-promises: "error" */
/* eslint no-such: 2 */
/* eslint @typescript-eslint/no-mixed-enums: "sometimes" */
/* eslint no-alert: "sometimes" */
/* eslint no-alert: 2 no-console: 1 */
/* eslint no-debugger: 2 no-eval: 1 no-with: 2 */
/* eslint no-empty: [2, */
/* eslint @typescript-eslint/restrict-template-expressions: "error" */
/* eslint-env node */
/* global first, second: writable, third: nope, fourth:readonly */
/* exported unusedName */
// eslint @typescript-eslint/no-array-delete: "off"
declare const p: Promise<number>;
declare const list: number[];
async function f() {
  p;
  await 1;
  delete list[0];
  void `${1}`;
  for (const key in list) {
    void key;
  }
}
export { f };
// A name with nothing after its `:`, a repeated name (its last value counts) and the order of a
// JavaScript object, where the names that are indexes come first.
/* global empty:, twice:nope, twice:off, b:bad, 2:worse, 1:worst, __proto__:nope */
